import React, { useEffect } from "react";

const TelegramInit: React.FC = () => {
    useEffect(() => {
        const initData = (window as any).Telegram.WebApp.initData;
        fetch("/api/telegram_verify", {
            method: "POST",
            headers: {
                "Content-Type": "application/x-www-form-urlencoded",
            },
            body: new URLSearchParams({ initData }),
        })
            .then((response) => response.text())
            .then((data) => console.log(data))
            .catch((error) => console.error("Error:", error));
    }, []);

    return (
        <div>
            <h1>Telegram WebApp Initialization</h1>
        </div>
    );
};

export default TelegramInit;
