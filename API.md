# Base

```ts
BASE_URL = 'https://game.releasethekraken.io/backend'
```

# Athorization

### POST /api/anonymous_session
```ts
REQUEST {
    referrer_id: string | undefined
}
RESPONSE {
    jwt: string
}
```


### POST /api/telegram_session
```ts
REQUEST {
    initData: string
    referrer_id: string | undefined
}
RESPONSE {
    jwt: string
}
```


# Websocet

```ts
BASE_URL = 'wss://game.releasethekraken.io/backend/ws'
QUERY {
    jwt: string
}
```

## Structs:

### Level 
```ts
{
    id: string;
    quotaPeriod: number;
    quotaAmount: number;
    calmPeriod: number;
}
```

### User 
```ts
{
    id: string;
    userId: string;
    isBlocked: boolean;
    level: Level;
    nickname: string;
    sessionStart: number;
    sessionLeft: number;
    sessionUntil: number;
    sessionTaps: number;
    sessionTapsLeft: number;
    taps: number;
    calmUntil: number;
    refUser: User | null;
}
```


## Methods:

### base sheme: 
```ts
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "...",
    "params": any,
}
```




### getUser
```ts
REQUEST {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getUser"
}
RESPONSE {
    "jsonrpc": "2.0",
    "id": 1,
    "result": User | undefined,
    "error": undefined | Error,
}
```

### sendTaps
```ts
REQUEST {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "sendTaps",
    "params": [
        {
            x: number,
            y: number
        }
    ]
}
RESPONSE {
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        userInfo: User,
        error?: string
    },
    "error": undefined | Error,
}
```

### updateProfile
```ts
REQUEST {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "updateProfile",
    "params": {
        nickName?: string,
        wallet?: string
    }
}
RESPONSE {
    "jsonrpc": "2.0",
    "id": 1,
    "result": [
        {
            userInfo: User,
            error?: string
        }
    ],
    "error": undefined | Error,
}
```

### getTopUsers
```ts
REQUEST {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getTopUsers",
    "params": {
        limit: number,
    }
}
RESPONSE {
    "jsonrpc": "2.0",
    "id": 1,
    "result": [
        User, 
        User, 
        ...
    ],
    "error": undefined | Error,
}
```


### getTopReferrals
```ts
REQUEST {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getTopReferrals",
    "params": {
        limit: number,
    }
}
RESPONSE {
    "jsonrpc": "2.0",
    "id": 1,
    "result": [
        User, 
        User, 
        ...
    ],
    "error": undefined | Error,
}
```