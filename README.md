ranger
======

Ranger is a HTTP partial content Range header enforcement script

### Requirements:
  * nginx with LUA module enabled ( luaJit prefered ). Check http://wiki.nginx.org/HttpLuaModule

### Install:
  * checkout this module
  * don't forget to retrieve dependencies with
```sh
$ git submodule update --init
```
  * update/create your nginx.conf from conf/default.conf 

### Configuration:
  * edit content.lua:
    * block_size: block size (default 256k)
    * backend: URL for backend where data will be fetch (default http://127.0.0.1:8080/) 
    * fcttl: Time to cache HEAD requests (default 30s)
