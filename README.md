# smart-home-agent

<p align="center">
  <img src="Screenshot_1.png" width="200" alt="App screenshot 1">
  &nbsp;&nbsp;
  <img src="Screenshot_2.png" width="200" alt="App screenshot 2">
</p>

### Mobile app architecture
The Flutter app uses a simple layered, MVC-like design with `setState` for state management. It polls the Pi's Flask server every 5 seconds. The server sends only raw sensor values, and the app works out the comfort level itself.

| Layer | What's in it | Role |
|---|---|---|
| **Data** | `Reading`, `Api` | Fetches JSON from `http://<IP>:5000/data` and turns it into a model |
| **Logic** | `computeComfort()`, `comfortInfo()` | Decides the comfort level and the advice text |
| **State / controller** | `_HomePageState` | Holds the IP, latest reading and history; runs the polling timer |
| **UI** | `MetricCard`, `_ComfortCard`, `RoomSelector`, etc. | Stateless widgets that display the data |

---
### Python dependencies
- flask==3.1.1
- sense_hat==2.6.1

`json`, `os` and `time` are part of Python's standard library, so nothing to install.

---
### Run
Start the sensor loop in the background, then the server:
> python3 main.py & python3 server.py

---
