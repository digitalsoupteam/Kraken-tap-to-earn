FROM tarantool/tarantool:2.11
RUN tarantoolctl rocks install https://github.com/tarantool/websocket/raw/master/websocket-scm-1.rockspec
RUN tarantoolctl rocks install https://github.com/moonlibs/sync/raw/master/rockspecs/sync-scm-1.rockspec
#RUN apt-get update && apt-get install -y git 
#RUN tt rocks install https://github.com/tarantool/websocket/raw/master/websocket-scm-1.rockspec
ENV TT_APP_NAME=app
CMD ["tarantool", "app.lua"]
