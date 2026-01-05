# Alex Chen's Blog

A modern personal tech blog built with Node.js.

## Features

- 🎨 Modern dark theme design
- 📱 Fully responsive layout
- ⚡ Fast and lightweight
- 🐳 Docker-ready deployment

## Getting Started

### Local Development

```bash
npm install
npm start
```

### Docker Deployment

```bash
docker build -t alex-blog .
docker run -p 8080:8080 -e SERVER_PORT=8080 alex-blog
```

Then visit `http://localhost:8080`

## Tech Stack

- Node.js 18+
- Pure HTML/CSS/JS (no frameworks)
- Docker for containerization

## License

MIT © Alex Chen
