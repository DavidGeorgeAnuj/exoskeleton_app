Ah, my apologies for the misunderstanding and the incomplete response earlier. I understand now. You want the final, complete README.md file, ready for your GitHub repository, formatted professionally in Markdown.

Here is the complete and final README.md file, incorporating all the best elements we've discussed.

Real-Time Control System for a Rehabilitation Exoskeleton

This repository contains the complete software ecosystem developed during a research internship at the Indian Institute of Technology (IIT) Goa. The system provides a real-time interface for controlling and monitoring a robotic exoskeleton.

The project is structured as a monorepo containing:

The Python Back-End Server (server.py) - Designed for deployment on the Raspberry Pi.

The Flutter Mobile Application - Designed to be built on a separate development machine.

A Web Dashboard (web/) - Designed to be deployed on the Raspberry Pi.

(Space for Diagram)
(Replace this line with ![System Architecture Diagram](./assets/system_diagram.png) after adding the image to an assets folder.)

✨ Core Features

High-Performance Asynchronous Server: A robust Python server built with asyncio to handle multiple clients and high-frequency hardware I/O without blocking.

Real-Time Bidirectional Communication: Low-latency control and data telemetry using the WebSocket protocol.

Advanced Safety Framework: A stateful, server-authoritative Admin/User Role-Based Access Control (RBAC) system designed to eliminate command race conditions.

Turnkey Operational System: The server is configured as an auto-launching service on the Raspberry Pi, enabling a system-ready state in under two seconds from boot.

Self-Hosted Ecosystem: The entire back-end, including the web client, is hosted on the Raspberry Pi, creating a "plug-and-play" appliance that requires no internet access.

Rich Data Visualization & Export: The client applications feature interactive, real-time plotting and a one-touch CSV export for offline analysis.

🏛️ Project Structure

This repository contains all necessary components for the software ecosystem.

Generated code
.
├── server.py             # The core Python WebSocket server for the Raspberry Pi
├── lib/                  # Flutter application source code (Dart)
│   ├── main.dart         # Main UI, state management, and WebSocket logic
│   ├── plot_screen.dart    # UI for real-time data visualization
│   └── settings_screen.dart # UI for IP config and role management
├── android/              # Android-specific build files for Flutter
├── web/                  # Web dashboard source files
├── pubspec.yaml          # Flutter project dependencies
└── README.md             # This file

🚀 Server Setup and Deployment (on Raspberry Pi)

This is the primary guide to deploy the core control server and web dashboard onto the Raspberry Pi.

Prerequisites

A Raspberry Pi (3B+ or newer recommended) with Raspberry Pi OS.

A compatible CAN Hat configured and enabled on the OS level.

T-Motor actuator connected via the CAN bus.

Python 3.8+ installed.

Installation Steps

Transfer Required Files to Raspberry Pi:
You only need the server-side components. Transfer the following from this repository to a directory on your Raspberry Pi (e.g., /home/pi/exoskeleton_server):

server.py

web/ (the entire folder containing index.html, etc.)

Configure CAN Interface:
Ensure your can0 interface is enabled. This typically involves editing /boot/config.txt. Follow your CAN Hat manufacturer's instructions. After rebooting, bring the interface up:

Generated bash
sudo ip link set can0 up type can bitrate 1000000
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

Set up Python Environment:
Navigate to your project directory on the Pi:

Generated bash
cd /home/pi/exoskeleton_server
python3 -m venv venv
source venv/bin/activate
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

Install Python Dependencies:

Generated bash
pip install websockets numpy
pip install git+https://github.com/mit-biomimetics/TMotorCANControl.git
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

Configure the Server:

Open server.py for editing: nano server.py.

Update the HOST variable to your Raspberry Pi's static IP address.

Set a strong, unique ADMIN_PASSWORD.

Run the Server Manually (for Testing):

Generated bash
python server.py
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

The server should start on your configured IP at port 8765. You can now connect with a client to test.

(Recommended) Deploy as an Auto-Launching Service:
To create a robust, "turnkey" system, configure the server to run automatically on boot using systemd.

Create a service file: sudo nano /etc/systemd/system/exoskeleton_server.service

Paste the following configuration, updating the paths to match your setup:

Generated ini
[Unit]
Description=Exoskeleton Control WebSocket Server
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/exoskeleton_server
ExecStart=/home/pi/exoskeleton_server/venv/bin/python server.py
Restart=always

[Install]
WantedBy=multi-user.target
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Ini
IGNORE_WHEN_COPYING_END

Enable and start the service:

Generated bash
sudo systemctl enable exoskeleton_server.service
sudo systemctl start exoskeleton_server.service
sudo systemctl status exoskeleton_server.service
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

(Note: You will also need a simple HTTP server to serve the web/ directory. python -m http.server is a simple option that can also be run as a service.)

📱 (Optional) Flutter Client Setup

The included Flutter application serves as a comprehensive mobile client. It should be built on a separate development computer (Windows/macOS/Linux) with the Flutter environment pre-installed.

To build the app, the development machine must have a fully configured Flutter environment, including the Flutter SDK, the Android SDK and platform tools, and a working Android Debug Bridge (ADB) connection to a physical device or emulator. The setup process is as follows: first, clone the repository to your development machine using git clone. Next, run flutter pub get in the project's root directory to download all the necessary library dependencies. Before building, you must update the server's IP address by editing the _serverIp variable in the lib/main.dart file to match your Raspberry Pi's static IP. Finally, with a device connected, initiate the build and deployment by running the flutter run command. This will compile the app, install the resulting APK on your target device via ADB, and launch it.

📂 Project Artifacts & Appendices

The following links provide supplementary materials for this project, including demonstration videos, diagrams, and documentation.

[Appendix A: Application Demo Videos]
(https://drive.google.com/drive/folders/1Df3j8A_1_ootU3SVb6Kt8D-iakJCMEIw?usp=drive_link)

[Appendix B: System Diagrams and Setup Images]
(https://drive.google.com/drive/folders/1OTffhjF-SXtsBoFuVkU0myWLeUjoNKjQ?usp=drive_link)

[Appendix C: Presentation and Project Documentation]
(https://drive.google.com/drive/folders/10Lh98yQQELuLaW8o34tGA-WfBLv5QXZ2?usp=drive_link)

[Appendix D: Android Application Build Files]
(https://drive.google.com/drive/folders/13lT7tyjh6SGhUyu3BfOKSJrkctPwtVil?usp=drive_link)

Acknowledgements

This project was developed as part of a research internship at the Indian Institute of Technology (IIT) Goa. It supports a research initiative involving expertise from both IIT Goa and the National Institute of Technology Karnataka (NITK), funded by the DST-SERB.

Mentor: Dr. Sheron Figarado (IIT Goa)

Author: David George Anuj (Rajagiri School of Engineering and Technology)

📜 License

This project is licensed under the MIT License - see the LICENSE file for details.
