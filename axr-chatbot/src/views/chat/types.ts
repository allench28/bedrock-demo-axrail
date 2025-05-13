type Message = {
  messageId: string;
  contents: string;
  sender: "user" | "assistant";
  messageStop?: boolean;
};

export type { Message };
