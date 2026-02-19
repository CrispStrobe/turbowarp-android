// Intercepts new WebSocket(url) when url matches /scratch/ble or /scratch/bt
// and routes it through webkit.messageHandlers.scratchLink instead.
class ScratchLink {

    constructor(url) {
        // Match any WSS/WS connection ending in /scratch/ble or /scratch/bt
        const scratchLinkPattern = /^wss?:\/\/.*\/scratch\/(ble|bt)$/;

        if (!scratchLinkPattern.test(url)) {
            // Pass through standard WebSockets (multiplayer, cloud data, etc.)
            return new ScratchLink.WebSocket(url);
        }

        this.url = url;
        this._open();
    }

    _open() {
        this.socketId = ScratchLink.socketId;
        ScratchLink.sockets.set(ScratchLink.socketId, this);
        ScratchLink.socketId++;

        this._postMessage({
            method: 'open',
            socketId: this.socketId,
            url: this.url
        });

        setTimeout(() => {
            if (this.onopen) this.onopen();
        }, 100);
    }

    close() {
        this._postMessage({
            method: 'close',
            socketId: this.socketId
        });

        if (this.onclose) this.onclose();
        ScratchLink.sockets.delete(this.socketId);
    }

    send(message) {
        this._postMessage({
            method: 'send',
            socketId: this.socketId,
            jsonrpc: message
        });
    }

    _postMessage(message) {
        webkit.messageHandlers.scratchLink.postMessage(JSON.stringify(message));
    }

    handleMessage(message) {
        if (this.onmessage) {
            this.onmessage({ data: message });
        }
    }
}

ScratchLink.socketId = 0;
ScratchLink.sockets = new Map();

ScratchLink.CONNECTING = window.WebSocket.CONNECTING;
ScratchLink.OPEN = window.WebSocket.OPEN;
ScratchLink.CLOSING = window.WebSocket.CLOSING;
ScratchLink.CLOSED = window.WebSocket.CLOSED;

ScratchLink.WebSocket = window.WebSocket;
window.WebSocket = ScratchLink;
