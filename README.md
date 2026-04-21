# Claude Code — AI LAB

A collection of mini-projects built in this workspace.

---

## Snake Game

A classic snake game served via a simple Node.js HTTP server.

### Requirements

- Node.js 18 or later (uses built-in `http` module, no dependencies needed)

### Start the server

```bash
node snake-game/server.js
```

Then open your browser and go to:

```
http://localhost:3001
```

### How to play

| Key | Action |
|-----|--------|
| Arrow Keys / WASD | Move the snake |
| P | Pause / Resume |

- Eat the red food to grow and score points
- Every 100 points increases the level (and speed)
- Avoid hitting the walls or yourself

---

## AI Meeting Minutes Assistant (Nuxt App)

A Nuxt 4 app that transcribes audio recordings and generates Word document meeting minutes using the Gemini API.

### Requirements

- Node.js 18+
- A `GEMINI_API_KEY` environment variable

### Start the dev server

```bash
npm install
GEMINI_API_KEY=your_key_here npm run dev
```

Open: `http://localhost:3000`
