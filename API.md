# Websocet

url: wss://host:3000/ws

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

### sendTaps: 
```ts
request payload = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "sendTaps",
    "params": {
        "userId": "string",
        "taps": [
            {
                "x": 178.15,
                "y": 250.01
            },
            ...
        ]
    },
}

return Array<{ userInfo: User; error?: string }>
```

### getUser: 
```ts
request payload = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getUser"
}

return User
```

### getTopUsers: 
```ts
request payload = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getTopUsers",
    "params": {
        "limit": 100,
    }
}

return Array<User>
```
