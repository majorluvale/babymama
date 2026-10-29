// Vercel entry point: the whole Express app runs as one serverless function (see vercel.json).
// `npm run vercel-build` compiles src/ to dist/ before Vercel bundles this file.
module.exports = require('../dist/app').createApp();
