import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { motion } from "framer-motion";
import { SendHorizonal } from "lucide-react";
import { useEffect, useRef } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
// import "./ChatPage.css";
import { Spinner } from "@/components/ui/spinner";
import { ChatProvider, useChat } from "./useChat";

// Custom hook for smooth scrolling
const useSmoothScroll = () => {
  return (element: HTMLElement, offset: number) => {
    element.scrollTo({
      top: element.scrollHeight - element.clientHeight + offset,
      behavior: "smooth",
    });
  };
};

export const ChatPage = () => {
  return (
    <ChatProvider>
      <Screen />
    </ChatProvider>
  );
};

const Screen = () => {
  const { messages, handleSubmitForm, form, connectionStatus } = useChat();

  const messageContainerRef = useRef<HTMLDivElement>(null);
  const smoothScroll = useSmoothScroll();

  useEffect(() => {
    if (messageContainerRef.current) {
      smoothScroll(
        messageContainerRef.current,
        messageContainerRef.current.scrollHeight
      );
    }
  }, [JSON.stringify(messages)]);

  const { handleSubmit, register } = form;

  return (
    <div className="relative flex flex-col h-full w-full overflow-hidden">
      <div
        ref={messageContainerRef}
        className="flex flex-1 w-full flex-col-reverse overflow-y-auto p-4 scrollbar-hide"
      >
        <div className="w-full max-w-screen-md mx-auto pt-[72px] space-y-4">
          {messages.map((message, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.15 }}
              className={`flex ${
                message.sender === "user" ? "justify-end" : "justify-start"
              }`}
            >
              <div
                className={`px-3 py-2 text-sm rounded-lg max-w-[480px] ${
                  message.sender === "user"
                    ? "bg-blue-600/80 text-white backdrop-blur-md"
                    : "bg-white/70"
                }`}
              >
                <ReactMarkdown
                  remarkPlugins={[remarkGfm]}
                  className={`prose prose-sm prose-headings:text-base break-words ${
                    message.sender === "user"
                      ? "text-white"
                      : "text-grey-800 py-1"
                  }`}
                  components={{
                    a: LinkRenderer,
                    li: ({ children }) => <li className="">{children}</li>,
                  }}
                >
                  {message.contents}
                </ReactMarkdown>

                {message?.sender === "assistant" &&
                  !message?.messageStop &&
                  !message?.contents && (
                    <div className="relative h-4 w-fit flex items-center justify-center">
                      <div className="w-1 h-1 rounded-full animate-ping duration-700 bg-blue-500 left-0 top-0 bottom-0"></div>
                    </div>
                  )}
              </div>
            </motion.div>
          ))}
        </div>
      </div>

      <div className="px-4 pt-0 pb-4 md:pb-8 w-full flex flex-col justify-start items-center">
        <form
          id="my-form"
          onSubmit={handleSubmit(handleSubmitForm)}
          className="has-[:focus-visible]:border-alpha-600 relative rounded-xl border shadow transition-colors duration-300 ease-in max-w-screen-md mx-auto w-full"
        >
          {/* email-icon, lock-icon, pw-icon, axr-logo logo.svg no-rec */}
          <div className="flex flex-row items-center relative rounded-xl bg-white py-1 pl-2 pr-1.5 w-full">
            <Input
              // name="message"
              {...register("message")}
              maxLength={500}
              type="text"
              placeholder="Type a message..."
              className="resize-none overflow-auto w-full flex-1 bg-transparent text-sm border-none shadow-none outline-none ring-0 pl-1"
              disabled={connectionStatus !== "Open"}
            />
            <Button
              type="submit"
              disabled={connectionStatus !== "Open"}
              className="h-full p-2 aspect-square rounded-[8px]"
            >
              {connectionStatus !== "Open" ? (
                <Spinner size="small" className="w-4 h-4 text-white" />
              ) : (
                <SendHorizonal className="w-4 h-4" />
              )}
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
};

const LinkRenderer = ({ href, children }: any) => {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className="text-blue-500 underline"
    >
      {children?.replaceAll("%20", " ")}
    </a>
  );
};
