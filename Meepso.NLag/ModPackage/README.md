# No Lag

### How it works
Because godot is single threaded, the game ends up spending a large ammount of time per frame just trying to read network packets.

No Lag is a simple solution to this problem, it uses a separate thread to read network packets and then sends them to the main thread to be processed!

### How to use

Just install like any other GDWeave mod!