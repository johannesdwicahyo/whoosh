import { useState, useRef, useCallback, useEffect } from "react";
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Platform,
} from "react-native";
import { StatusBar } from "expo-status-bar";
import { API_URL, DEFAULT_API_KEY } from "../config";

type Message = {
  role: "user" | "assistant";
  content: string;
};

// SSE parser that works on all platforms (no ReadableStream needed)
async function fetchSSE(
  url: string,
  options: RequestInit,
  onChunk: (content: string) => void,
  onDone: () => void,
  onError: (error: string) => void
) {
  try {
    const response = await fetch(url, options);

    if (!response.ok) {
      const error = await response.text();
      try {
        const parsed = JSON.parse(error);
        onError(parsed.error || "Request failed");
      } catch {
        onError(`HTTP ${response.status}`);
      }
      return;
    }

    // For web: use ReadableStream if available
    if (Platform.OS === "web" && response.body?.getReader) {
      const reader = response.body.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const text = decoder.decode(value, { stream: true });
        parseSSELines(text, onChunk);
      }
      onDone();
      return;
    }

    // For React Native: read full response text then parse
    // (RN doesn't support streaming fetch, but the response is small enough)
    const text = await response.text();
    parseSSELines(text, onChunk);
    onDone();
  } catch (err: any) {
    onError(err.message || "Connection error");
  }
}

function parseSSELines(text: string, onChunk: (content: string) => void) {
  const lines = text.split("\n");
  for (const line of lines) {
    if (line.startsWith("data: ") && line !== "data: [DONE]") {
      try {
        const data = JSON.parse(line.slice(6));
        const content = data.choices?.[0]?.delta?.content;
        if (content) onChunk(content);
      } catch {
        // Skip malformed lines
      }
    }
  }
}

export default function ChatScreen() {
  const [apiKey, setApiKey] = useState(DEFAULT_API_KEY);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [health, setHealth] = useState<"ok" | "down" | "checking">("checking");
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef("");

  // Check health on mount
  useEffect(() => {
    fetch(`${API_URL}/health`)
      .then((r) => r.json())
      .then((data) => setHealth(data.status === "ok" ? "ok" : "down"))
      .catch(() => setHealth("down"));
  }, []);

  const sendMessage = useCallback(async () => {
    if (!input.trim() || loading) return;

    const userMsg = input.trim();
    setInput("");
    setMessages((prev) => [...prev, { role: "user", content: userMsg }]);
    setLoading(true);
    contentRef.current = "";

    // Add empty assistant message
    setMessages((prev) => [...prev, { role: "assistant", content: "" }]);

    await fetchSSE(
      `${API_URL}/chat/stream`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Api-Key": apiKey,
        },
        body: JSON.stringify({ message: userMsg }),
      },
      // onChunk
      (content) => {
        contentRef.current += content;
        const current = contentRef.current;
        setMessages((prev) => {
          const updated = [...prev];
          updated[updated.length - 1] = { role: "assistant", content: current };
          return updated;
        });
      },
      // onDone
      () => setLoading(false),
      // onError
      (error) => {
        setMessages((prev) => {
          const updated = [...prev];
          updated[updated.length - 1] = {
            role: "assistant",
            content: `Error: ${error}`,
          };
          return updated;
        });
        setLoading(false);
      }
    );
  }, [input, apiKey, loading]);

  return (
    <View style={styles.container}>
      <StatusBar style="light" />

      {/* Health indicator */}
      <View style={styles.healthBar}>
        <View
          style={[
            styles.healthDot,
            {
              backgroundColor:
                health === "ok"
                  ? "#4ade80"
                  : health === "down"
                  ? "#f87171"
                  : "#fbbf24",
            },
          ]}
        />
        <Text style={styles.healthText}>
          {health === "ok"
            ? `API Connected (${API_URL})`
            : health === "down"
            ? `API Offline (${API_URL})`
            : "Checking..."}
        </Text>
      </View>

      {/* API Key input */}
      <View style={styles.apiKeyRow}>
        <Text style={styles.label}>API Key:</Text>
        <TextInput
          style={styles.apiKeyInput}
          value={apiKey}
          onChangeText={setApiKey}
          placeholder="sk-..."
          placeholderTextColor="#666"
        />
      </View>

      {/* Messages */}
      <ScrollView
        ref={scrollRef}
        style={styles.messages}
        onContentSizeChange={() =>
          scrollRef.current?.scrollToEnd({ animated: true })
        }
      >
        {messages.length === 0 && (
          <View style={styles.emptyState}>
            <Text style={styles.emptyTitle}>Whoosh Chat</Text>
            <Text style={styles.emptySubtitle}>
              Send a message to start chatting
            </Text>
          </View>
        )}
        {messages.map((msg, i) => (
          <View
            key={i}
            style={[
              styles.messageBubble,
              msg.role === "user" ? styles.userBubble : styles.assistantBubble,
            ]}
          >
            <Text
              style={[
                styles.messageText,
                msg.role === "user" && styles.userText,
              ]}
            >
              {msg.content || "..."}
            </Text>
          </View>
        ))}
        {loading && (
          <ActivityIndicator style={{ marginTop: 8 }} color="#818cf8" />
        )}
      </ScrollView>

      {/* Input */}
      <View style={styles.inputRow}>
        <TextInput
          style={styles.input}
          value={input}
          onChangeText={setInput}
          placeholder="Type a message..."
          placeholderTextColor="#666"
          onSubmitEditing={sendMessage}
          editable={!loading}
          returnKeyType="send"
        />
        <TouchableOpacity
          style={[styles.sendButton, loading && styles.sendButtonDisabled]}
          onPress={sendMessage}
          disabled={loading}
        >
          <Text style={styles.sendText}>Send</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#0f0f23" },
  healthBar: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: "#16213e",
  },
  healthDot: { width: 8, height: 8, borderRadius: 4, marginRight: 8 },
  healthText: { color: "#94a3b8", fontSize: 12 },
  apiKeyRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: "#16213e",
    borderBottomWidth: 1,
    borderBottomColor: "#1e293b",
  },
  label: { color: "#94a3b8", fontSize: 12, marginRight: 8 },
  apiKeyInput: {
    flex: 1,
    color: "#e2e8f0",
    fontSize: 12,
    backgroundColor: "#1e293b",
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  messages: { flex: 1, padding: 16 },
  emptyState: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    paddingTop: 100,
  },
  emptyTitle: { color: "#e2e8f0", fontSize: 24, fontWeight: "bold" },
  emptySubtitle: { color: "#64748b", fontSize: 14, marginTop: 8 },
  messageBubble: {
    maxWidth: "80%",
    padding: 12,
    borderRadius: 12,
    marginBottom: 8,
  },
  userBubble: {
    backgroundColor: "#4f46e5",
    alignSelf: "flex-end",
    borderBottomRightRadius: 4,
  },
  assistantBubble: {
    backgroundColor: "#1e293b",
    alignSelf: "flex-start",
    borderBottomLeftRadius: 4,
  },
  messageText: { color: "#e2e8f0", fontSize: 15, lineHeight: 22 },
  userText: { color: "#ffffff" },
  inputRow: {
    flexDirection: "row",
    padding: 12,
    backgroundColor: "#16213e",
    borderTopWidth: 1,
    borderTopColor: "#1e293b",
  },
  input: {
    flex: 1,
    backgroundColor: "#1e293b",
    color: "#e2e8f0",
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 10,
    fontSize: 15,
    marginRight: 8,
  },
  sendButton: {
    backgroundColor: "#4f46e5",
    borderRadius: 20,
    paddingHorizontal: 20,
    justifyContent: "center",
  },
  sendButtonDisabled: { opacity: 0.5 },
  sendText: { color: "#fff", fontWeight: "600", fontSize: 15 },
});
