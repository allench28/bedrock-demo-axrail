import { createContext, useContext, useEffect, useState } from "react";

import useWebSocket, { ReadyState } from "react-use-websocket";
import { v4 as uuid } from "uuid";
import { Message } from "./types";

import { useForm } from "react-hook-form";
import { WEBSOCKET_ENDPOINT } from "@/constants/apiEndpoints";

const ChatContext = createContext<any>(null);
const ChatProvider = ({ children }: { children: JSX.Element }) => {
  const value = useChatController();

  return <ChatContext.Provider value={value}>{children}</ChatContext.Provider>;
};

const useChat = () => {
  const context = useContext(ChatContext);
  if (!context) {
    throw new Error("useSmartChatContext must be used within a ChatProvider");
  }
  return context;
};

export const useChatController = () => {
  const [messages, setMessages] = useState<Message[]>([]);

  const { sendJsonMessage, readyState } = useWebSocket(WEBSOCKET_ENDPOINT, {
    shouldReconnect: (closeEvent) => {
      console.log("Close Event:", closeEvent);
      return true;
    },
    onMessage: (event) => {
      const searchResult = JSON.parse(event?.data);

      const contents = searchResult?.contents;
      const messageId = searchResult?.messageId;
      const messageStop = searchResult?.messageStop;

      const messageIndex = messages?.findIndex(
        (message) => message?.messageId === messageId
      );

      if (messageIndex > -1) {
        const existingMessage = messages[messageIndex];

        const currentContents = existingMessage?.contents || "";

        let newMessages = messages;
        newMessages[messageIndex] = {
          ...existingMessage,
          contents: currentContents + contents,
          messageStop: messageStop,
        };

        setMessages(newMessages);

        return;
      }

      const newBotMessage: Message = {
        messageId: messageId,
        contents: contents,
        sender: "assistant",
        messageStop: !!messageStop,
      };

      setMessages((prev) => prev.concat(newBotMessage));
    },
  });

  const form = useForm({
    defaultValues: {
      message: "",
    },
  });

  const { setValue } = form;

  const handleSubmitForm = (e: any) => {
    const inputText = e.message;

    const id = uuid();
    const bot_id = uuid();

    if (e) {
      const newUserMessage: Message = {
        messageId: id,
        contents: inputText,
        sender: "user",
      };

      const newBotMessage: Message = {
        messageId: bot_id,
        contents: "",
        sender: "assistant",
        messageStop: false,
      };

      const newMessages = [newUserMessage, newBotMessage];

      setMessages((prev) => prev.concat(newMessages));

      sendJsonMessage({
        message: inputText.trim(),
        messageId: bot_id,
      });

      setValue("message", "");
    }
  };

  const connectionStatus = {
    [ReadyState.CONNECTING]: "Connecting",
    [ReadyState.OPEN]: "Open",
    [ReadyState.CLOSING]: "Closing",
    [ReadyState.CLOSED]: "Closed",
    [ReadyState.UNINSTANTIATED]: "Uninstantiated",
  }[readyState];

  useEffect(() => {
    console.log("Connection Status:", connectionStatus);
  }, [readyState]);

  return {
    messages,
    setMessages,
    handleSubmitForm,
    form,
    connectionStatus,
  };
};

export { ChatContext, ChatProvider, useChat };
