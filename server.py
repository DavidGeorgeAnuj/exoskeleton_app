# Python WebSocket Server for T-Motor Control
# Runs on the Raspberry Pi (or device connected to CAN bus)
# Now includes Admin/User privilege system for commands and password for initial Admin request
# ------------------------------------------------------------------------------------

import asyncio
import websockets
import json
import time
import traceback
import numpy as np
import warnings
import sys

try:
    # Assuming the user's local mit_can.py has the provided MIT_Params structure
    from TMotorCANControl.mit_can import TMotorManager_mit_can, MIT_Params, _TMotorManState
    print("Successfully imported TMotorManager_mit_can")
except ImportError:
    print("Error: TMotorCANControl library not found. Please ensure it's in your path.")
    print("Install with: pip install git+https://github.com/mit-biomimetics/TMotorCANControl.git")
    sys.exit(1)


# --- Motor Parameters ---
Type = 'AK80-9'
ID = 2

# --- WebSocket Server Configuration ---
HOST = '10.196.34.53' #'10.42.0.1'
PORT = 8765

# --- Admin Password Configuration ---
# !! IMPORTANT: Change this to a strong password !!
ADMIN_PASSWORD = "mysecretpassword"
# -------------------------------------


# --- Control Loop Frequency ---
MOTOR_UPDATE_FREQUENCY = 100 # Hz
MOTOR_UPDATE_INTERVAL = 1.0 / MOTOR_UPDATE_FREQUENCY # Time interval in seconds

# --- WebSocket State Send Frequency ---
STATE_SEND_FREQUENCY = 50 # Hz (e.g., half the update rate)
STATE_SEND_INTERVAL = 1.0 / STATE_SEND_FREQUENCY # Time interval in seconds


# --- Global shared state variables ---
shared_motor_state = {}

# --- Global variable to track the 'Admin' client ---
# Stores the websocket object of the client that has the 'Admin' role
current_admin_websocket = None # Renamed from current_doctor_websocket

# --- Global variable to track if the Admin password has been set in this server session ---
is_admin_password_set = False # New state variable, False on server start


# --- Async Task for Continuous Motor Update ---
async def motor_update_task(dev: TMotorManager_mit_can, shared_state_arg: dict, interval=MOTOR_UPDATE_INTERVAL):
    """
    Continuously updates motor state and updates shared state.
    """
    print("Task 'motor_update_task' started.")

    try:
        while True:
            start_time = time.time()
            current_motor_state = {}

            # --- Update Motor State ---
            try:
                # This sends the current command and gets the latest state
                # The command values in dev._command are updated by receive_commands
                # The mode in dev._control_state is updated by receive_commands
                dev.update()
                current_motor_state = {
                    "timestamp": time.time(),
                    "position": dev.position,
                    "velocity": dev.velocity,
                    "current": dev.current_qaxis,
                    "temperature": dev.temperature,
                    "error": dev.error, # 0 if no error
                    "motor_type": dev.type,
                    "motor_id": dev.ID,
                    "control_mode": dev._control_state.name, # Get the mode the server is COMMANDING
                    "cmd_position": dev._command.position, # Get the command being sent *by the server*
                    "cmd_velocity": dev._command.velocity,
                    "cmd_current": dev._command.current,
                    "cmd_kp": dev._command.kp,
                    "cmd_kd": dev._command.kd,
                }
                # Add error description based on motor error code
                if current_motor_state["error"] != 0:
                     error_desc = MIT_Params['ERROR_CODES'].get(current_motor_state['error'], 'Unknown Motor Error')
                     current_motor_state["error_description"] = f"Motor Error Code {current_motor_state['error']}: {error_desc}"
                     print(f"Motor reported error: {current_motor_state['error_description']}")
                else:
                     current_motor_state["error_description"] = ""


            except RuntimeError as e:
                print(f"Motor Runtime Error during dev.update(): {e}")
                # Use the last known good state or a default error state
                current_motor_state = shared_state_arg.copy() if shared_state_arg else {}
                current_motor_state.update({
                     "timestamp": time.time(),
                     "error": -1, # Use a distinct server-side error code
                     # Keep existing motor error if any, but add runtime error description
                     "error_description": f"Server Runtime Error: {e}",
                     "is_runtime_error": True,
                })
                # Decide on shutdown/recovery strategy here if critical

            except Exception as e:
                print(f"Unexpected error during dev.update() in motor_update_task: {e}")
                traceback.print_exc()
                current_motor_state = shared_state_arg.copy() if shared_state_arg else {}
                current_motor_state.update({
                    "timestamp": time.time(),
                    "error": -2, # Use a distinct server-side error code
                    # Keep existing motor error if any, but add unexpected error description
                    "error_description": f"Server Unexpected Error: {e}",
                    "is_unexpected_error": True,
                })
                # Decide on shutdown/recovery strategy here if critical

            # --- Update Shared State (even on error, to signal status) ---
            if current_motor_state:
                # Ensure we don't overwrite the role here, it's added in send_state
                # shared_state_arg.clear() # Don't clear, just update
                shared_state_arg.update(current_motor_state)


            # --- Maintain Update Frequency ---
            end_time = time.time();
            elapsed_time = end_time - start_time;
            sleep_duration = interval - elapsed_time;
            if sleep_duration > 0:
                 await asyncio.sleep(sleep_duration);


    except asyncio.CancelledError:
        print("Task 'motor_update_task' cancelled.")
    except Exception as e:
        print(f"Error in motor_update_task: {e}")
        traceback.print_exc()
    finally:
        print("Task 'motor_update_task' finished.")


# --- Async Task for Sending State to a Client ---
async def send_state(websocket, shared_state_arg: dict, interval=STATE_SEND_INTERVAL):
    """
    Async task to send the latest motor state from the shared variable to a client.
    Adds the client's role and the admin password requirement status to the state message.
    """
    global current_admin_websocket # Need to read the global variable
    global is_admin_password_set # Need to read the global variable

    print("Task 'send_state' started for a client.")
    try:
        while True:
            start_time = time.time()

            # --- Read the latest state from the shared variable ---
            latest_state = None
            if shared_state_arg:
                 latest_state = shared_state_arg.copy()

            # --- Prepare and Send the state data as JSON ---
            if latest_state:
                try:
                    state_to_client = latest_state.copy()

                    # --- Add the client's role ---
                    state_to_client["role"] = "Admin" if websocket == current_admin_websocket else "User" # Renamed Role
                    # --- Add the admin password required status ---
                    state_to_client["admin_password_required"] = not is_admin_password_set # Added new field
                    # -----------------------------

                    # Combine server errors and motor errors for display
                    error_description_list = [] # Use a list to build description
                    if latest_state.get("error", 0) != 0:
                         error_description_list.append(latest_state.get("error_description", f"Motor Error Code: {latest_state.get('error')}"))
                    if latest_state.get("is_runtime_error"):
                         # Ensure the correct key is used for runtime error message
                         error_description_list.append(latest_state.get("error_description", "Unknown Server Runtime Error"))
                    if latest_state.get("is_unexpected_error"):
                          # Ensure the correct key is used for unexpected error message
                         error_description_list.append(latest_state.get("error_description", "Unknown Server Unexpected Error"))


                    state_to_client["error_description"] = ", ".join(error_description_list) if error_description_list else ""
                    state_to_client["is_error"] = latest_state.get("error", 0) != 0 or latest_state.get("is_runtime_error", False) or latest_state.get("is_unexpected_error", False)

                    # Remove internal server error flags before sending (error_description handles the text)
                    state_to_client.pop("is_runtime_error", None)
                    state_to_client.pop("is_unexpected_error", None)


                    await websocket.send(json.dumps(state_to_client))

                except websockets.exceptions.ConnectionClosed:
                     print("Client WebSocket connection closed while sending state.")
                     break
                except Exception as e:
                     print(f"Error sending state data over websocket: {e}")
                     traceback.print_exc()
            else:
                # If shared_motor_state is empty (e.g., just started), wait a bit
                await asyncio.sleep(0.01)
                continue

            # --- Maintain Send Frequency ---
            end_time = time.time();
            elapsed_time = end_time - start_time;
            sleep_duration = interval - elapsed_time;
            if sleep_duration > 0:
                 await asyncio.sleep(sleep_duration);


    except asyncio.CancelledError:
        print("Task 'send_state' cancelled.")
    except Exception as e:
        print(f"Error in send_state task: {e}")
        traceback.print_exc()
    finally:
        print("Task 'send_state' finished for this client.")


# --- Async Task for Receiving Commands ---
async def receive_commands(websocket, dev: TMotorManager_mit_can):
    """
    Async task to receive and process commands from the WebSocket client.
    Commands modify the internal dev._command and dev._control_state.
    Only accepts standard commands from the 'Admin' client.
    Handles 'request_admin_role' and 'release_admin_role'.
    """
    global current_admin_websocket # Need to read and write to the global variable
    global is_admin_password_set # Need to read and write to the global variable
    global ADMIN_PASSWORD # Need to read the global variable

    print("Task 'receive_commands' started for a client.")
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                command_type = data.get("command")
                print(f"Received command from {websocket.remote_address}: {command_type}") # Log received command type

                # --- Handle Role Management Commands (Allowed from any client) ---
                if command_type == "request_admin_role": # Renamed Command
                     client_password = data.get("password") # Get password from data

                     if current_admin_websocket is None:
                         # No Admin currently holding the role
                         if not is_admin_password_set:
                             # Password is required for the first time
                             if client_password is not None and client_password == ADMIN_PASSWORD:
                                 current_admin_websocket = websocket
                                 is_admin_password_set = True # Mark password as set for this session
                                 print(f"Client {websocket.remote_address} granted Admin role (password set).")
                                 # Send success with updated password status
                                 await websocket.send(json.dumps({
                                     "status": "success",
                                     "message": "You are now the Admin.",
                                     "role": "Admin", # Send updated role back in status
                                     "admin_password_required": not is_admin_password_set # Send updated status
                                 }))
                             else:
                                 # Password incorrect or missing
                                 print(f"Client {websocket.remote_address} requested Admin role (password required) with incorrect/missing password.")
                                 await websocket.send(json.dumps({
                                     "status": "error",
                                     "message": "Incorrect or missing password.",
                                     "role": "User", # Role remains User
                                     "admin_password_required": not is_admin_password_set # Status remains True
                                 }))
                         else:
                             # Password already set, grant role without password check
                             current_admin_websocket = websocket
                             print(f"Client {websocket.remote_address} granted Admin role (password already set).")
                             await websocket.send(json.dumps({
                                  "status": "success",
                                  "message": "You are now the Admin.",
                                  "role": "Admin", # Send updated role back in status
                                  "admin_password_required": not is_admin_password_set # Status should be False
                             }))
                     else:
                         # Admin role is already taken
                         print(f"Client {websocket.remote_address} requested Admin role, but it's already taken.")
                         await websocket.send(json.dumps({
                              "status": "error",
                              "message": "Admin role is already taken.",
                              "role": "User", # Role remains User
                              "admin_password_required": not is_admin_password_set # Send current status
                         }))

                elif command_type == "release_admin_role": # Renamed Command
                     if websocket == current_admin_websocket:
                         current_admin_websocket = None
                         print(f"Client {websocket.remote_address} released Admin role.")
                         # Send confirmation back
                         await websocket.send(json.dumps({
                             "status": "success",
                             "message": "You have released the Admin role.",
                             "role": "User", # Send updated role back in status
                             "admin_password_required": not is_admin_password_set # Password status does not change on release
                         }))
                     else:
                         print(f"Client {websocket.remote_address} tried to release Admin role, but isn't the Admin.")
                         # Send rejection back
                         await websocket.send(json.dumps({
                             "status": "error",
                             "message": "You are not the Admin.",
                             "role": "User" if websocket != current_admin_websocket else "Admin", # Send their *actual* current role
                             "admin_password_required": not is_admin_password_set # Send current status
                         }))

                # --- Handle Standard Motor Control Commands (Only from Admin) ---
                # Check if the client is the current Admin
                elif websocket != current_admin_websocket: # Changed variable name
                    print(f"Rejected command '{command_type}' from non-Admin client {websocket.remote_address}") # Changed text
                    # Send rejection back
                    await websocket.send(json.dumps({
                         "status": "error",
                         "message": "You are not the Admin. Cannot send commands.", # Changed text
                         "role": "User", # Their role is User
                         "admin_password_required": not is_admin_password_set # Send current status
                    }))
                    continue # Skip processing the rest of the command

                # If we reach here, it's a standard command AND the client is the Admin
                elif command_type == "set_full_state_params":
                    try:
                        p_des = float(data.get("p_des", 0.0))
                        v_des = float(data.get("v_des", 0.0))
                        i_des = float(data.get("i_des", 0.0))
                        kp = float(data.get("kp", 0.0))
                        kd = float(data.get("kd", 0.0))
                        print(f"Admin Command: set_full_state_params P={p_des:.3f}, V={v_des:.3f}, I={i_des:.3f}, Kp={kp:.1f}, Kd={kd:.2f}") # Changed text

                        # It's generally safer to transition to the desired mode before setting params
                        # Or, let set_impedance_gains_real_unit_full_state_feedback handle mode setting
                        # The library's methods are usually designed for this.
                        # If set_impedance_gains requires the mode to be set first:
                        # dev._control_state = _TMotorManState.FULL_STATE

                        # Set internal commands/gains. These will be sent on the next dev.update()
                        dev.set_impedance_gains_real_unit_full_state_feedback(K=kp, B=kd)
                        dev.position = p_des
                        dev.velocity = v_des
                        dev.current_qaxis = i_des

                        await websocket.send(json.dumps({"status": "success", "message": "Full state params updated."}))

                    except (ValueError, TypeError) as e:
                         print(f"Admin Command Error: Parameter parsing failed: {e}") # Changed text
                         await websocket.send(json.dumps({"status": "error", "message": f"Invalid number format: {e}"}))
                    except Exception as e:
                         print(f"Admin Command Error: Setting full state params failed: {e}") # Changed text
                         traceback.print_exc()
                         await websocket.send(json.dumps({"status": "error", "message": f"Server error setting params: {e}"}))


                elif command_type == "power_off":
                     print("Admin Command: Received power_off command.") # Changed text
                     # Set internal commands to zero as a safety measure before power_off
                     dev.set_impedance_gains_real_unit_full_state_feedback(K=0.0, B=0.0) # Zero gains first
                     dev.position = 0.0
                     dev.velocity = 0.0
                     dev.current_qaxis = 0.0
                     dev._control_state = _TMotorManState.IDLE # Transition to idle internally

                     try:
                          dev.power_off() # Send the CAN command
                          print("Admin Command: Motor power_off command sent via CAN.") # Changed text
                          await websocket.send(json.dumps({"status": "success", "message": "Motor power off command sent."}))
                     except Exception as e:
                           print(f"Admin Command Error sending power_off command: {e}") # Changed text
                           traceback.print_exc()
                           await websocket.send(json.dumps({"status": "error", "message": f"Error sending power_off: {e}"}))


                elif command_type == "power_on":
                     print("Admin Command: Received power_on command.") # Changed text
                     try:
                         dev.power_on()
                         print("Admin Command: Motor power_on command sent via CAN.") # Changed text
                         # --- After power_on, server defaults to MIT and safe gains ---
                         # This is consistent with how the server starts
                         dev._control_state = _TMotorManState.FULL_STATE # Default to MIT after power on
                         dev._command.position = 0.0
                         dev._command.velocity = 0.0
                         dev._command.current = 0.0
                         # Using min gains as a safe default after power on
                         dev._command.kp = MIT_Params.get(dev.type, {}).get('Kp_min', 0.0) # Use .get for safety
                         dev._command.kd = MIT_Params.get(dev.type, {}).get('Kd_min', 0.0) # Use .get for safety
                         print(f"Admin Command: Internal state set to MIT with default gains (Kp={dev._command.kp}, Kd={dev._command.kd}) after power on.") # Changed text
                         # ------------------------------------------------------------------
                         await websocket.send(json.dumps({"status": "success", "message": "Motor power on command sent."}))

                     except Exception as e:
                          print(f"Admin Command Error sending power_on command: {e}") # Changed text
                          traceback.print_exc()
                          await websocket.send(json.dumps({"status": "error", "message": f"Error sending power_on: {e}"}))

                elif command_type == "zero":
                     print("Admin Command: Received zero command.") # Changed text
                     # Note: The app sends zero params first, then zero command.
                     # The server's receive_commands task processes messages sequentially from one client.
                     # If the zero command arrives immediately after set_full_state_params with zeros,
                     # the motor_update_task might send one frame with zero params before the zero command.
                     # This is generally acceptable.
                     try:
                          dev.set_zero_position()
                          print("Admin Command: Zeroing command sent via CAN.") # Changed text
                          await websocket.send(json.dumps({"status": "success", "message": "Motor zero command sent."}))
                     except Exception as e:
                          print(f"Admin Command Error sending zero command: {e}") # Changed text
                          traceback.print_exc()
                          await websocket.send(json.dumps({"status": "error", "message": f"Error sending zero: {e}"}))

                elif command_type == "noop":
                     pass # Do nothing for noop

                else:
                    print(f"Admin Command: Unknown command type received: {command_type}") # Changed text
                    await websocket.send(json.dumps({"status": "error", "message": f"Unknown command: {command_type}"}))

            except json.JSONDecodeError:
                print(f"Received invalid JSON from {websocket.remote_address}: {message}")
                try: await websocket.send(json.dumps({"status": "error", "message": "Invalid JSON received"}))
                except websockets.exceptions.ConnectionClosed: pass
            except Exception as e:
                print(f"Error processing received message from {websocket.remote_address}: {e}")
                traceback.print_exc()
                try: await websocket.send(json.dumps({"status": "error", "message": f"Server error processing message: {e}"}))
                except websockets.exceptions.ConnectionClosed: pass

    except websockets.exceptions.ConnectionClosed:
        print(f"Client {websocket.remote_address} WebSocket connection closed in receive_commands task.")
    except asyncio.CancelledError:
         print(f"Task 'receive_commands' cancelled for {websocket.remote_address}.")
    except Exception as e:
        print(f"Error in receive_commands task for {websocket.remote_address}: {e}")
        traceback.print_exc()
    print(f"Task 'receive_commands' finished for client {websocket.remote_address}.")


# --- Async WebSocket Handler ---
async def handler(websocket, dev: TMotorManager_mit_can, shared_state_arg: dict):
    """
    Handles a new WebSocket connection.
    Starts receive and send tasks.
    Cleans up admin role if the admin client disconnects.
    """
    global current_admin_websocket # Need to read the global variable
    global is_admin_password_set # Need to read the global variable (for initial state message)

    print(f"Client connected from {websocket.remote_address}")

    # Send initial state immediately upon connection
    if shared_state_arg:
        initial_state = shared_state_arg.copy()
        initial_state["role"] = "Admin" if websocket == current_admin_websocket else "User" # Renamed Role
        initial_state["admin_password_required"] = not is_admin_password_set # Added password status
        try:
            await websocket.send(json.dumps(initial_state))
        except websockets.exceptions.ConnectionClosed:
            print(f"Warning: Client {websocket.remote_address} disconnected before receiving initial state.")


    receive_task = asyncio.create_task(receive_commands(websocket, dev))
    send_task = asyncio.create_task(send_state(websocket, shared_state_arg))

    try:
        # Wait for either task to finish (usually due to connection closure)
        await asyncio.gather(receive_task, send_task)
    except asyncio.CancelledError:
        print(f"Handler tasks cancelled for client {websocket.remote_address}.")
    except Exception as e:
         print(f"Unexpected error in handler gather for client {websocket.remote_address}: {e}")
         traceback.print_exc()
    finally:
        # --- Connection closed, clean up ---
        print(f"Client disconnected: {websocket.remote_address}")
        # If this client was the Admin, release the role
        if websocket == current_admin_websocket: # Changed variable name
            current_admin_websocket = None
            print(f"Admin client {websocket.remote_address} disconnected. Admin role released.") # Changed text

        # Ensure all tasks for this client are cancelled
        for task in [receive_task, send_task]:
            if not task.done():
                task.cancel()
                try:
                    # Add a small timeout to wait for graceful cancellation
                    await asyncio.wait_for(task, timeout=1.0)
                except asyncio.TimeoutError:
                    print(f"Task {task.get_name()} for {websocket.remote_address} did not cancel gracefully.")
                except asyncio.CancelledError:
                     pass # Expected exception
                except Exception as e:
                     print(f"Error waiting task cancellation for {websocket.remote_address}: {e}")
                     traceback.print_exc()

        print(f"Handler for {websocket.remote_address} finished.")


# --- WebSocket Server Setup ---
async def run_websocket_server(dev: TMotorManager_mit_can, shared_state_arg: dict):
    """
    Sets up and runs the WebSocket server.
    Listens for incoming connections and starts handler tasks for each.
    """
    # We need to use functools.partial or a lambda to pass dev and shared_state_arg
    # to the handler function when serve calls it.
    # A lambda is simpler here.
    server = await websockets.serve(
        lambda ws: handler(ws, dev, shared_state_arg),
        HOST,
        PORT
    )
    print(f"WebSocket server started on ws://{HOST}:{PORT}")
    await server.wait_closed()
    print("WebSocket server closed.")


# --- Main Async Execution Entry Point ---
async def main():
    """
    Initializes motor, sets default mode, starts continuous motor task,
    and then starts the WebSocket server.
    Initializes global state variables.
    """
    global shared_motor_state # Declare intent to use the global variable
    global current_admin_websocket # Declare intent to use the global variable
    global is_admin_password_set # Declare intent to use the global variable

    # --- Initialize global state variables ---
    current_admin_websocket = None
    is_admin_password_set = False
    shared_motor_state = {} # Ensure it's empty at the start
    # ------------------------------------------

    motor_manager = None
    motor_task = None
    websocket_server_task = None


    try:
        print(f"Attempting to connect to motor {ID} ({Type}...)...")
        # Using the 'with' statement ensures dev.power_off() is called on exit
        with TMotorManager_mit_can(motor_type=Type, motor_ID=ID, max_mosfett_temp=75) as dev:
            motor_manager = dev
            print(f"Motor {ID} ({Type}) connected.")

            # --- Set initial internal state and mode to MIT and default gains ---
            dev._control_state = _TMotorManState.FULL_STATE # Default to MIT mode
            dev._command.position = 0.0
            dev._command.velocity = 0.0
            dev._command.current = 0.0
            # Using min gains as a safe default
            dev._command.kp = MIT_Params.get(dev.type, {}).get('Kp_min', 0.0) # Use .get for safety
            dev._command.kd = MIT_Params.get(dev.type, {}).get('Kd_min', 0.0) # Use .get for safety

            print(f"Internal command values set to zero, mode set to MIT with default gains (Kp={dev._command.kp:.2f}, Kd={dev._command.kd:.2f}).")
            # ------------------------------------------------------------------------------

            try:
                 # Perform initial update to confirm communication and send initial MIT command
                 await asyncio.sleep(0.1) # Small delay after connection
                 dev.update() # <-- This sends the set mode and initial commands
                 print("Initial motor state updated and MIT command sent.")
                 # Populate shared state with initial data
                 shared_motor_state.update({
                     "timestamp": time.time(),
                     "position": dev.position,
                     "velocity": dev.velocity,
                     "current": dev.current_qaxis,
                     "temperature": dev.temperature,
                     "error": dev.error,
                     "motor_type": dev.type,
                     "motor_id": dev.ID,
                     "control_mode": dev._control_state.name, # Get the mode the server is COMMANDING
                     "cmd_position": dev._command.position,
                     "cmd_velocity": dev._command.velocity,
                     "cmd_current": dev._command.current,
                     "cmd_kp": dev._command.kp,
                     "cmd_kd": dev._command.kd,
                     "error_description": MIT_Params['ERROR_CODES'].get(dev.error, 'Unknown Motor Error') if dev.error != 0 else "",
                     # Server-side error flags are added in send_state, not stored here.
                 })

            except RuntimeError as e:
                 print(f"CRITICAL ERROR: Could not communicate with motor after initial connection/MIT command: {e}")
                 print("Please check motor power, CAN connections, and CAN interface ('can0') status.")
                 # Update shared state with critical server error
                 shared_motor_state.update({
                     "timestamp": time.time(),
                     "error": -1, # Use a distinct server-side error code
                     "error_description": f"CRITICAL SERVER ERROR during initial motor check: {e}",
                     "is_runtime_error": True,
                 })
                 raise # Re-raise to stop execution

            except Exception as e:
                 print(f"CRITICAL ERROR: Unexpected error during initial motor update: {e}")
                 traceback.print_exc()
                  # Update shared state with critical server error
                 shared_motor_state.update({
                     "timestamp": time.time(),
                     "error": -2, # Use a distinct server-side error code
                     "error_description": f"CRITICAL SERVER ERROR during initial motor check: {e}",
                     "is_unexpected_error": True,
                 })
                 raise # Re-raise to stop execution


            print("Motor initialized and ready.")

            # --- Start the continuous motor update task ---
            motor_task = asyncio.create_task(
                motor_update_task(dev, shared_motor_state, MOTOR_UPDATE_INTERVAL)
            )
            print("Continuous motor update task started.")

            # --- Start the WebSocket server task ---
            # Run this as a task so main doesn't block forever on serve
            websocket_server_task = asyncio.create_task(
                 run_websocket_server(dev, shared_motor_state)
            )
            print("WebSocket server task started.")

            # Keep main running until the server task is done (e.g., KeyboardInterrupt)
            await websocket_server_task


    except asyncio.CancelledError:
        print("Main task cancelled.")
    except Exception as e:
        print(f"An error occurred during motor setup or server execution: {e}")
        traceback.print_exc()
    finally:
         print("Main function cleanup.")
         # Ensure motor is powered off on graceful shutdown
         if motor_manager:
             try:
                 print("Attempting to power off motor...")
                 motor_manager.power_off()
                 print("Motor power off command sent.")
             except Exception as e:
                 print(f"Error sending motor power off during cleanup: {e}")
                 traceback.print_exc()

         # Cancel the motor update task if it's running
         if motor_task and not motor_task.done():
             print("Cancelling motor update task...")
             motor_task.cancel()
             try:
                 # Wait a bit for the task to finish cancelling
                 await asyncio.wait_for(motor_task, timeout=5.0)
                 print("Motor update task cancelled successfully.")
             except asyncio.TimeoutError:
                 print("Motor update task did not cancel gracefully within timeout.")
             except asyncio.CancelledError:
                  pass # Expected
             except Exception as e:
                  print(f"Error while waiting for motor task cancellation: {e}")
                  traceback.print_exc()

         # Cancel the server task if it's running
         if websocket_server_task and not websocket_server_task.done():
             print("Cancelling WebSocket server task...")
             websocket_server_task.cancel()
             try:
                  await asyncio.wait_for(websocket_server_task, timeout=5.0)
                  print("WebSocket server task did not cancel gracefully within timeout.")
             except asyncio.TimeoutError:
                 print("WebSocket server task did not cancel gracefully within timeout.")
             except asyncio.CancelledError:
                 pass # Expected
             except Exception as e:
                 print(f"Error while waiting for server task cancellation: {e}")
                 traceback.print_exc()

         print("Main function finished.")


# --- Standard Python Script Entry Point ---
if __name__ == '__main__':
    print("Starting server script...")
    try:
        # asyncio.run() will run the main coroutine until it completes
        # It handles the event loop creation and closing.
        asyncio.run(main())
    except SystemExit:
        print("SystemExit requested. Shutting down.")
    except KeyboardInterrupt:
         print("\nKeyboard interrupt received. Shutting down.")
         # asyncio.run handles the graceful shutdown on Ctrl+C
    except Exception as e:
         print(f"An unexpected error occurred during asyncio run: {e}")
         traceback.print_exc()

    print("Script finished.")