import React, { useState } from "react";
import "./App.css";
import X from "@twa-dev/sdk";
import TelegramInit from "./hooks/telegramInit";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let WebApp = (X as unknown as any).default;

const App: React.FC = () => {
    const [count, setCount] = useState(0);

    return (
        <>
            <TelegramInit />
            <div className="card">
                <button onClick={() => setCount((count) => count + 1)}>
                    count is {count}
                </button>
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
        </>
    );
};

export default App;
