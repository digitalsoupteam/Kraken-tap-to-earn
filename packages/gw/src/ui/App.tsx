import React, { useEffect, useRef, useState } from "react";
import "./App.css";
import X from "@twa-dev/sdk";
import TelegramInit from "./hooks/telegramInit";
import { TntUserInfo } from "../types";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let WebApp = (X as unknown as any).default;

const useWebSocket = (token: string) => {
    const [socket, setSocket] = useState<WebSocket | null>(null);
    const [isConnected, setIsConnected] = useState(false);
    const reconnectIntervalRef = useRef<Timer | null>(null);

    const connectWebSocket = () => {
        const ws = new WebSocket("/ws?jwt=" + token);

        ws.onopen = () => {
            console.log("WebSocket connection opened");
            setIsConnected(true);
            clearInterval(reconnectIntervalRef.current!);
        };

        ws.onmessage = (message) => {
            console.log("Received message:", message.data);
        };

        ws.onclose = () => {
            console.log("WebSocket connection closed");
            setIsConnected(false);
            attemptReconnect();
        };

        ws.onerror = (error) => {
            console.error("WebSocket error:", error);
            localStorage.removeItem("token");
        };

        setSocket(ws);
    };

    const attemptReconnect = () => {
        if (!reconnectIntervalRef.current) {
            reconnectIntervalRef.current = setInterval(() => {
                console.log("Attempting to reconnect...");
                connectWebSocket();
            }, 5000);
        }
    };

    useEffect(() => {
        connectWebSocket();

        return () => {
            if (socket) {
                socket.close();
            }
            clearInterval(reconnectIntervalRef.current!);
        };
    }, [token]);

    return { socket, isConnected };
};

const useLocalStorageMonitor = (key: string) => {
    const [value, setValue] = useState(() => localStorage.getItem(key));

    useEffect(() => {
        const handleStorageChange = (event: any) => {
            if (event.key === key) {
                setValue(event.newValue);
            }
        };

        window.addEventListener("storage", handleStorageChange);

        return () => {
            window.removeEventListener("storage", handleStorageChange);
        };
    }, [key]);

    return value;
};

const Connecting: React.FC = () => {
    return <div>Connecting...</div>;
};

const Game: React.FC<{ token: string }> = ({ token }) => {
    const [count, setCount] = useState(0);
    const { socket, isConnected } = useWebSocket(token);
    if (!isConnected) {
        return <Connecting />;
    }
    const handleTap = () => {
        if (isConnected && socket) {
            socket?.send(
                JSON.stringify({
                    jsonrpc: "2.0",
                    id: 1,
                    method: "sendTaps",
                    params: [{ x: 0, y: 0 }],
                })
            );
            setCount((count) => count + 1);
        }
    };

    const [userInfo, setUserInfo] = useState<TntUserInfo>();
    useEffect(() => {
        if (isConnected && socket) {
            socket?.send(
                JSON.stringify({
                    jsonrpc: "2.0",
                    id: 1,
                    method: "getUser",
                })
            );
        }
    });
    return (
        <div>
            <div className="card">
                <button onClick={handleTap}>count is {count}</button>
            </div>
            <div className="card">
                <button
                    onClick={() =>
                        WebApp.showAlert(
                            `Hello World! Current count is ${count}`
                        )
                    }
                >
                    Show Alert
                </button>
            </div>
        </div>
    );
};

const App: React.FC = () => {
    const storage = useLocalStorageMonitor("token");

    return (
        <>
            <TelegramInit />
            {storage ? <Game token={storage} /> : undefined}
        </>
    );
};

export default App;
