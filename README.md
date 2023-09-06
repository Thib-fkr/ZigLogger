# ZigLogger

A basic keylogger written in Zig.

The goal of this project is to learn about system programming concepts and play around with Zig.

This project is for educational purposes only (see the [License](./LICENSE) for usage information).

## How to

Command to launch the program :
```bash
sudo -E zig run keylogger_linux.zig -lc -lxkbcommon -lxcb -lxkbcommon-x11 -lwayland-client
```
*(zig being the zig version 0.11)*

## Next Steps

- [ ] (linux) Test the program on Xorg  
- [ ] (linux) Find a way to store the keymap string somewhere and not compute it every time  
- [ ] (linux) Implement the handling of modifier keys  