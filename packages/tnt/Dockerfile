FROM tarantool/tarantool:2.10
RUN tarantoolctl rocks install https://github.com/tarantool/websocket/raw/master/websocket-scm-1.rockspec
ENV TT_APP_NAME=app
CMD ["tarantool", "app.lua"]
