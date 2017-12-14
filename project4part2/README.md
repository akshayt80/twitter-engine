# Project4part2

**Group members**

| Name                 | UFID     | Email ID                 |
| :------------------: | :------: | :----------------------: |
| Anmol Khanna         | 65140549 | anmolkhanna93@ufl.edu    |
| Akshat Singh Jetawat | 22163183 | akshayt80@ufl.edu        |

# Project Defination

- The objective of this project is to implement a twitter clone using websockets in phoenix and elixir. Also. we need
  a JSON based API that shows all the messages and their replies including any errors if any.


> Sever Compilation

```
mix deps.get
mix phx.server
```
 
> Initialize and running Phoenix server

``` 
mix phx.server
```
  
# Functionality Details

- In server we have used channels provided by Phoenix framework which utilizes webspckets by default.
- We have used ETS as a in memory data store for elixir

# Client Details

- We have used phoenix channel client(https://github.com/ryo33/phoenix-channel-client) which uses websockets to connect to the server.
- Client provides interactive options to user to select from.

> Client compilation
```
cd phoenix_client
mix deps.get
mix escript.build
./phoenix_client server_ip i.e. ./phoenix_client 127.0.0.1
```

Finding:
1. When there is no activity at client for 30 seconds then connection to server websocket get terminated. To workaround this we are reconnecting to the server when the client receives close signal from server.

Demo Video Link : https://youtu.be/-NnkU_YDVxI


