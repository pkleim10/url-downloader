const express = require('express');
const { exec, spawn } = require('child_process');
const path = require('path');
const os = require('os');

const app = express();
const PORT = 3000;

// Middleware
app.use(express.json());
app.use(express.static('.'));

// Security: Only allow localhost connections
app.use((req, res, next) => {
    if (req.ip !== '127.0.0.1' && req.ip !== '::1' && req.ip !== '::ffff:127.0.0.1') {
        return res.status(403).json({ error: 'Access denied. Only localhost connections allowed.' });
    }
    next();
});

// Sanitize prefix input
function sanitizePrefix(prefix) {
    if (!prefix) return '';
    // Remove potentially dangerous characters, but allow spaces
    return prefix.replace(/[^a-zA-Z0-9_ -]/g, '_');
}

// Validate URL input
function isValidUrl(string) {
    try {
        new URL(string);
        return true;
    } catch (_) {
        return false;
    }
}

// Download endpoint
app.post('/download', (req, res) => {
    const { url, prefix } = req.body;
    
    // Validate inputs
    if (!url || typeof url !== 'string') {
        return res.status(400).json({ error: 'URL is required' });
    }
    
    if (!isValidUrl(url)) {
        return res.status(400).json({ error: 'Invalid URL format' });
    }
    
    // Sanitize prefix
    const sanitizedPrefix = sanitizePrefix(prefix);
    
    // Get the full path to Downloads folder
    const downloadsPath = path.join(os.homedir(), 'Downloads');
    
    // Build output filename with conditional prefix
    const outputTemplate = sanitizedPrefix ? 
        `${downloadsPath}/${sanitizedPrefix}-%(title)s.%(ext)s` : 
        `${downloadsPath}/%(title)s.%(ext)s`;
    
    // Build yt-dlp command arguments
    const args = [
        url,
        '-f', 'best[height<=1080]/best',
        '--impersonate', 'chrome:macos-14',
        '-o', outputTemplate
    ];

    console.log(`Executing: yt-dlp ${args.join(' ')}`);
    
    // Use spawn instead of exec for long-running processes
    const ytdlp = spawn('yt-dlp', args);
    
    let stdout = '';
    let stderr = '';
    
    // Collect stdout
    ytdlp.stdout.on('data', (data) => {
        stdout += data.toString();
        console.log('yt-dlp stdout:', data.toString());
    });
    
    // Collect stderr
    ytdlp.stderr.on('data', (data) => {
        stderr += data.toString();
        console.log('yt-dlp stderr:', data.toString());
    });
    
    // Handle process completion
    ytdlp.on('close', (code) => {
        if (code !== 0) {
            console.error('yt-dlp exited with code:', code);
            return res.status(500).json({ 
                error: 'Download failed',
                output: stderr || `Process exited with code ${code}`
            });
        }
        
        console.log('yt-dlp completed successfully');
        res.json({ 
            success: true,
            output: stdout || 'Download completed successfully'
        });
    });
    
    // Handle process errors
    ytdlp.on('error', (error) => {
        console.error('yt-dlp error:', error);
        return res.status(500).json({ 
            error: 'Download failed',
            output: error.message
        });
    });
});

// SSE Download endpoint (streams yt-dlp output with progress)
app.get('/download-stream', (req, res) => {
    const { url, prefix } = req.query;
    
    // Validate inputs
    if (!url || typeof url !== 'string') {
        res.write(`data: ${JSON.stringify({ type: 'error', message: 'URL is required' })}\n\n`);
        res.end();
        return;
    }
    
    if (!isValidUrl(url)) {
        res.write(`data: ${JSON.stringify({ type: 'error', message: 'Invalid URL format' })}\n\n`);
        res.end();
        return;
    }
    
    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    
    // Sanitize prefix
    const sanitizedPrefix = sanitizePrefix(prefix);
    
    // Get the full path to Downloads folder
    const downloadsPath = path.join(os.homedir(), 'Downloads');
    
    // Build output filename with conditional prefix
    const outputTemplate = sanitizedPrefix ? 
        `${downloadsPath}/${sanitizedPrefix}-%(title)s.%(ext)s` : 
        `${downloadsPath}/%(title)s.%(ext)s`;
    
    // Build yt-dlp command arguments
    const args = [
        url,
        '-f', 'best[height<=1080]/best',
        '--impersonate', 'chrome:macos-14',
        '-o', outputTemplate
    ];

    console.log(`Executing: yt-dlp ${args.join(' ')}`);
    
    // Use spawn to run yt-dlp
    const ytdlp = spawn('yt-dlp', args);
    
    // Stream stdout to client
    ytdlp.stdout.on('data', (data) => {
        const text = data.toString();
        const lines = text.replace(/\r/g, '\n').split('\n');
        lines.forEach(line => {
            if (line.trim()) {
                res.write(`data: ${JSON.stringify({ type: 'output', line: line })}\n\n`);
            }
        });
    });
    
    // Stream stderr to client (yt-dlp outputs progress here)
    ytdlp.stderr.on('data', (data) => {
        const text = data.toString();
        const lines = text.replace(/\r/g, '\n').split('\n');
        lines.forEach(line => {
            if (line.trim()) {
                res.write(`data: ${JSON.stringify({ type: 'output', line: line })}\n\n`);
            }
        });
    });
    
    // Handle process completion
    ytdlp.on('close', (code) => {
        if (code !== 0) {
            res.write(`data: ${JSON.stringify({ type: 'error', message: `Process exited with code ${code}` })}\n\n`);
        } else {
            res.write(`data: ${JSON.stringify({ type: 'done' })}\n\n`);
        }
        res.end();
    });
    
    // Handle process errors
    ytdlp.on('error', (error) => {
        res.write(`data: ${JSON.stringify({ type: 'error', message: error.message })}\n\n`);
        res.end();
    });
    
    // Handle client disconnect
    req.on('close', () => {
        ytdlp.kill();
        res.end();
    });
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Check if yt-dlp is installed
app.get('/check-ytdlp', (req, res) => {
    exec('yt-dlp --version', (error, stdout, stderr) => {
        if (error) {
            res.json({ 
                installed: false, 
                error: 'yt-dlp is not installed or not in PATH' 
            });
        } else {
            res.json({ 
                installed: true, 
                version: stdout.trim() 
            });
        }
    });
});

// Start server
app.listen(PORT, '127.0.0.1', () => {
    console.log(`URL Downloader server running at http://127.0.0.1:${PORT}`);
    console.log('Open your browser and navigate to the URL above');
    console.log('Make sure yt-dlp is installed: brew install yt-dlp');
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\nShutting down server...');
    process.exit(0);
});
