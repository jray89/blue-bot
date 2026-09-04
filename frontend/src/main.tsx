import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./index.css";

// Follow the OS colour scheme. The CSS keys off a `.dark` class so that a
// manual toggle can be added later without rewriting the theme.
const media = window.matchMedia("(prefers-color-scheme: dark)");
const applyScheme = (dark: boolean) =>
  document.documentElement.classList.toggle("dark", dark);

applyScheme(media.matches);
media.addEventListener("change", (event) => applyScheme(event.matches));

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
