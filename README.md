# LanChat

Flutter + Rust demo showcasing how simple the integration is!


<img src="./lanchat.png">

## Usage
`./run`

It requires cargo and flutter correctly configured.

## Info

The simplest code is here https://github.com/sigmaSd/LanChat/tree/simple_udp_multicast this shows the rust - flutter integration without unneeded complexity.

It uses only udp multicast for messaging which works great except for android which is hit/miss.

The master branch tracks the actual developement.

# Question/Answer

**Q- Sometimes Android is not discoverd**

*A- You can add peer adress manually, on android click on myip pane to see you tcp server adress, on the other peers click add ip and paste that in.*
