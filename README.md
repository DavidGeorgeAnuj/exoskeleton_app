# Real-Time Control System for a Rehabilitation Exoskeleton

This repository contains the complete software ecosystem developed during a research internship at the Indian Institute of Technology (IIT) Goa. The system provides a real-time interface for controlling and monitoring a robotic exoskeleton.

The project is structured as a monorepo containing:

- **Python Back-End Server (`server.py`)** – Designed for deployment on the Raspberry Pi.
- **Flutter Mobile Application** – Designed to be built on a separate development machine.
- **Web Dashboard (`web/`)** – Designed to be deployed on the Raspberry Pi.

> *(System architecture diagram placeholder: add with `![System Architecture Diagram](./assets/system_diagram.png)` after uploading the image to an `assets/` folder.)*

---

## Core Features

- **High-Performance Asynchronous Server**: Built with `asyncio`, the Python server handles multiple clients and high-frequency hardware I/O in real time.

- **Real-Time Bidirectional Communication**: WebSocket protocol is used for low-latency control and telemetry.

- **Advanced Safety Framework**: A stateful, server-authoritative RBAC (Role-Based Access Control) system prevents command race conditions.

- **Turnkey Operational System**: Server auto-launches on Raspberry Pi boot and reaches a ready state in under two seconds.

- **Self-Hosted Ecosystem**: The server and web dashboard are fully hosted on the Raspberry Pi—no internet required.

- **Rich Data Visualization & Export**: Client applications feature live plots and one-touch CSV data export.

---

## Project Structure

```
.
├── server.py               # Core Python WebSocket server for Raspberry Pi
├── lib/                    # Flutter app source code
│   ├── main.dart
│   ├── plot_screen.dart
│   └── settings_screen.dart
├── android/                # Flutter Android build system
├── web/                    # Web dashboard UI
├── pubspec.yaml            # Flutter dependency manager
└── README.md               # This file
```

---

## Server Setup and Deployment (Raspberry Pi)

### Prerequisites

- Raspberry Pi (3B+ or newer) with Raspberry Pi OS
- Compatible CAN Hat (configured)
- T-Motor actuator connected over CAN
- Python 3.8+

### Installation Steps

1. **Transfer Required Files to Raspberry Pi**  
   Copy the following to `/home/pi/exoskeleton_server`:
   - `server.py`
   - `web/` folder

2. **Configure CAN Interface**  
   Edit `/boot/config.txt` as needed for your CAN Hat. After reboot:
   ```bash
   sudo ip link set can0 up type can bitrate 1000000
   ```

3. **Set Up Python Environment**
   ```bash
   cd /home/pi/exoskeleton_server
   python3 -m venv venv
   source venv/bin/activate
   ```

4. **Install Dependencies**
   ```bash
   pip install websockets numpy
   pip install git+https://github.com/mit-biomimetics/TMotorCANControl.git
   ```

5. **Configure the Server**
   Open `server.py` and:
   - Set `HOST` to your Pi's static IP
   - Set a strong `ADMIN_PASSWORD`

6. **Run Manually for Testing**
   ```bash
   python server.py
   ```

7. **(Optional) Deploy as a Service**
   Create the systemd service file:
   ```bash
   sudo nano /etc/systemd/system/exoskeleton_server.service
   ```

   Paste:
   ```ini
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
   ```

   Enable and start:
   ```bash
   sudo systemctl enable exoskeleton_server.service
   sudo systemctl start exoskeleton_server.service
   sudo systemctl status exoskeleton_server.service
   ```

> You may also use `python3 -m http.server` to host the `web/` directory as an HTTP dashboard.

---

## Flutter Client Setup (Mobile App)

To build and run the Flutter mobile client:

### Prerequisites
- Flutter SDK installed
- Android SDK + Platform tools
- ADB installed
- Connected Android device or emulator

### Steps
1. Clone this repository:
   ```bash
   git clone https://github.com/your-username/exoskeleton_app.git
   cd exoskeleton_app
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Set server IP:  
   Edit `_serverIp` in `lib/main.dart` to match your Raspberry Pi’s IP.

4. Build and deploy:
   ```bash
   flutter run
   ```

---

## Project Artifacts & Appendices

You can access supplementary files and artifacts using the links below:

- [Appendix A: Application Demo Videos](https://drive.google.com/drive/folders/1Df3j8A_1_ootU3SVb6Kt8D-iakJCMEIw?usp=drive_link)

- [Appendix B: System Diagrams and Setup Images](https://drive.google.com/drive/folders/1OTffhjF-SXtsBoFuVkU0myWLeUjoNKjQ?usp=drive_link)

- [Appendix C: Presentation and Project Documentation](https://drive.google.com/drive/folders/10Lh98yQQELuLaW8o34tGA-WfBLv5QXZ2?usp=drive_link)

- [Appendix D: Android Application Build Files (.apk)](https://drive.google.com/drive/folders/13lT7tyjh6SGhUyu3BfOKSJrkctPwtVil?usp=drive_link)

---

## Acknowledgements

This project was developed as part of a research internship at the Indian Institute of Technology (IIT) Goa. It supports a research initiative involving collaboration between IIT Goa and the National Institute of Technology Karnataka (NITK), funded by the DST-SERB.

- **Mentor**: Dr. Sheron Figarado (IIT Goa)  
- **Author**: David George Anuj (Rajagiri School of Engineering and Technology)

---

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
