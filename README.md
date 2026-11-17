# EFREI DevOps – Project Lab 1

Minimal [Fastify](https://fastify.dev) API.

## Requirements

- Node.js >= 20

## Usage

```bash
npm install
npm start          # listens on http://0.0.0.0:3000
npm run dev        # restarts on file changes
npm test           # runs tests with node:test
```

Environment variables: `PORT` (default `3000`), `HOST` (default `0.0.0.0`).

## Endpoints

| Method | Path      | Response       |
|--------|-----------|----------------|
| GET    | `/health` | `200` · `OK`   |

```bash
curl http://localhost:3000/health
# OK
```


