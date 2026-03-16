import { Platform } from "react-native";

// Android emulator uses 10.0.2.2 for host machine localhost
// iOS simulator and web use localhost directly
const getDefaultUrl = () => {
  if (Platform.OS === "android") return "http://10.0.2.2:9292";
  return "http://localhost:9292";
};

export const API_URL = getDefaultUrl();
export const DEFAULT_API_KEY = "sk-demo-key";
