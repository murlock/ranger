DEPENDENCIES="pcre-devel openssl-devel zlib-devel"
yum install $DEPENDENCIES


LUAJIT_URL=http://luajit.org/download/LuaJIT-2.0.3.tar.gz
LUAJIT_FILE=$( basename $LUAJIT_URL )
LUAJIT_DIR=$( basename $LUAJIT_FILE .tar.gz )

if [ ! -f $LUAJIT_FILE ]; then
    wget $LUAJIT_URL -O $LUAJIT_FILE
fi

if [ -d $LUAJIT_DIR ]; then
    rm -rf $LUAJIT_DIR
fi
tar xf $LUAJIT_FILE
(
    cd $LUAJIT_DIR
    make
    sudo make install
)


NGX_DEVEL_URL=https://github.com/simpl/ngx_devel_kit/archive/v0.2.19.tar.gz
NGX_DEVEL_FILE=$( basename $NGX_DEVEL_URL )
NGX_DEVEL_DIR=$( basename $NGX_DEVEL_FILE .tar.gz | sed -e s/^v/ngx_devel_kit-/g )
if [ ! -f $NGX_DEVEL_FILE ]; then
    wget $NGX_DEVEL_URL -O $NGX_DEVEL_FILE
fi
if [ -d $NGX_DEVEL_DIR ]; then
    rm -rf $NGX_DEVEL_DIR
fi
tar xf $NGX_DEVEL_FILE
(
    cd $NGX_DEVEL_DIR
    make
)


NGX_LUA_URL=https://github.com/openresty/lua-nginx-module/archive/v0.9.13.tar.gz
NGX_LUA_FILE=$( basename $NGX_LUA_URL )
NGX_LUA_DIR=$( basename $NGX_LUA_FILE .tar.gz | sed -e s/^v/lua-nginx-module-/g )
if [ ! -f $NGX_LUA_FILE ]; then
    wget $NGX_LUA_URL -O $NGX_LUA_FILE
fi
if [ -d $NGX_LUA_DIR ]; then
    rm -rf $NGX_LUA_DIR
fi
tar xf $NGX_LUA_FILE

NGX_SRC_URL=http://nginx.org/download/nginx-1.6.2.tar.gz
NGX_SRC_FILE=$(basename $NGX_SRC_URL)
NGX_SRC_DIR=$(basename $NGX_SRC_FILE .tar.gz)

if [ ! -f $NGX_LUA_FILE ]; then
    wget $NGX_LUA_URL -O $NGX_LUA_FILE
fi
if [ -d $NGX_SRC_DIR ]; then
    rm -rf $NGX_SRC_DIR
fi
tar xf $NGX_SRC_FILE
(
    MOD1="$(readlink -e $NGX_DEVEL_DIR)"
    MOD2="$(readlink -e $NGX_LUA_DIR)"

    cd $NGX_SRC_DIR
    export LUAJIT_LIB=/usr/local/lib/
    export LUAJIT_INC=/usr//local/include/luajit-2.0/
    ./configure --prefix=/opt/nginx \
        --add-module=$MOD1 \
        --add-module=$MOD2 \
        --with-http_ssl_module
)
