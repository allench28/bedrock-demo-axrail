import {
  QueryCache,
  QueryClient,
  QueryClientProvider,
} from "@tanstack/react-query";
import toast, { Toaster } from "react-hot-toast";
import SiteContainer from "./components/generic/layouts/SiteContainer";
import { ChatPage } from "./views/chat/ChatPage";

function App() {
  const queryClient = new QueryClient({
    queryCache: new QueryCache({
      onError: (error) => {
        toast.error(`Something went wrong: ${error.message}`);
      },
    }),
  });
  return (
    <QueryClientProvider client={queryClient}>
      <SiteContainer>
        <ChatPage />
      </SiteContainer>
      <Toaster />
    </QueryClientProvider>
  );
}

export default App;
