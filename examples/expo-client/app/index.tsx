import { useState, useRef, useCallback } from "react";
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
} from "react-native";
import { StatusBar } from "expo-status-bar";
import { API_URL, DEFAULT_API_KEY } from "./config";

type Message = {
  role: "user" | "assistant";
  content: string;
};

export default function ChatScreen() {
  const [apiKey, setApiKey] = useState(DEFAULT_API_KEY);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [health, setHealth] = useState<"ok" | "down" | "checking">("checking");
  const scrollRef = useRef<ScrollView>(null);

  // Check health on mount
  useState(() => {
    fetch(`${API_URL}/health`)
      .then((r) => r.json())
      .then((data) => setHealth(data.status === "ok" ? "ok" : "down"))
      .catch(() => setHealth("down"));
  });

  const sendMessage = useCallback(async () => {
    if (!input.trim() || loading) return;

    const userMsg = input.trim();
    setInput("");
    setMessages((prev) => [...prev, { role: "user", content: userMsg }]);
    setLoading(true);

    try {
      const response = await fetch(`${API_URL}/chat/stream`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Api-Key": apiKey,
        },
        body: JSON.stringify({ message: userMsg }),
      });

      if (!response.ok) {
        const error = await response.json();
        setMessages((prev) => [
          ...prev,
          { role: "assistant", content: `Error: ${error.error}` },
        ]);
        return;
      }

      // Read SSE stream
      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      let assistantContent = "";

      setMessages((prev) => [...prev, { role: "assistant", content: "" }]);

      while (reader) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split("\n");

        for (const line of lines) {
          if (line.startsWith("data: ") && line !== "data: [DONE]") {
            try {
              const data = JSON.parse(line.slice(6));
              const content = data.choices?.[0]?.delta?.content || "";
              assistantContent += content;
              setMessages((prev) => {
                const updated = [...prev];
                updated[updated.length - 1] = {
                  role: "assistant",
                  content: assistantContent,
                };
                return updated;
              });
            } catch {
              // Skip malformed lines
            }
          }
        }
      }
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: "Connection error" },
      ]);
    } finally {
      setLoading(false);
    }
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
            ? "API Connected"
            : health === "down"
            ? "API Offline"
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
        {messages.map((msg, i) => (
          <View
            key={i}
            style={[
              styles.messageBubble,
              msg.role === "user" ? styles.userBubble : styles.assistantBubble,
            ]}
          >
            <Text style={styles.messageText}>{msg.content}</Text>
          </View>
        ))}
        {loading && <ActivityIndicator style={{ marginTop: 8 }} color="#818cf8" />}
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
    fontFamily: "monospace",
    backgroundColor: "#1e293b",
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  messages: { flex: 1, padding: 16 },
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
