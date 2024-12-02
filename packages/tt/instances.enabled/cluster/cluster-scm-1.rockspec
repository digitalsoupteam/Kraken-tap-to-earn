package      = 'cluster'
version      = 'scm-1'
source       = {
    url = '/dev/null',
}

dependencies = {
    'tarantool >= 3.1.0',
    'vshard == 0.1.27',
    'crud == 1.5.2',
    'websocket == 0.0.2',
    'metrics-export-role == 0.1.0-1',
}
build        = {
    type = 'none',
}
