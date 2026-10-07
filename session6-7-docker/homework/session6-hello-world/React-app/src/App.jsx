import { useState } from "react";

export default function App() {
  const [count, setCount] = useState(0);

  return (
    <main style={{ fontFamily: "sans-serif", textAlign: "center", marginTop: "15%" }}>
      <h1>Hello World from React in Docker!</h1>
      <p>Built with Vite (node:24-alpine) and served by Nginx – a multi-stage build.</p>
      <button onClick={() => setCount((c) => c + 1)}>Clicked {count} times</button>
    </main>
  );
}
