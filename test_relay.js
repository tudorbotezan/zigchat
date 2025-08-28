#!/usr/bin/env node

// Simple WebSocket test relay for Nostr protocol
// Responds to Nostr protocol messages

const WebSocket = require('ws');
const PORT = 8080;

const wss = new WebSocket.Server({ port: PORT });

console.log(`Test Nostr relay running on ws://localhost:${PORT}`);
console.log('Waiting for connections...\n');

// Store of fake messages
const fakeEvents = [
    {
        id: "event1",
        pubkey: "alice123",
        created_at: Math.floor(Date.now() / 1000) - 300,
        kind: 1,
        tags: [["t", "9q"]],
        content: "Welcome to the #9q channel! This is a test message.",
        sig: "fake_sig_1"
    },
    {
        id: "event2", 
        pubkey: "bob456",
        created_at: Math.floor(Date.now() / 1000) - 200,
        kind: 1,
        tags: [["t", "9q"]],
        content: "Hey everyone! Testing the WebSocket connection.",
        sig: "fake_sig_2"
    },
    {
        id: "event3",
        pubkey: "charlie789",
        created_at: Math.floor(Date.now() / 1000) - 100,
        kind: 1,
        tags: [["t", "9q"]],
        content: "Nostr protocol working great! Decentralized social media FTW!",
        sig: "fake_sig_3"
    }
];

wss.on('connection', (ws) => {
    console.log('Client connected');
    
    ws.on('message', (message) => {
        console.log('Received:', message.toString());
        
        try {
            const msg = JSON.parse(message);
            
            if (msg[0] === 'REQ') {
                const subscription_id = msg[1];
                const filters = msg[2] || {};
                
                console.log(`Subscription ${subscription_id} with filters:`, filters);
                
                // Send some fake events
                let eventsToSend = fakeEvents;
                
                // Filter by tags if specified
                if (filters['#t']) {
                    const tagFilter = filters['#t'];
                    eventsToSend = fakeEvents.filter(event => 
                        event.tags.some(tag => 
                            tag[0] === 't' && tagFilter.includes(tag[1])
                        )
                    );
                }
                
                // Apply limit if specified
                if (filters.limit) {
                    eventsToSend = eventsToSend.slice(0, filters.limit);
                }
                
                // Send events
                eventsToSend.forEach(event => {
                    const eventMsg = JSON.stringify(['EVENT', subscription_id, event]);
                    console.log('Sending event:', event.content);
                    ws.send(eventMsg);
                });
                
                // Send EOSE (end of stored events)
                const eoseMsg = JSON.stringify(['EOSE', subscription_id]);
                ws.send(eoseMsg);
                console.log('Sent EOSE');
                
                // Send new events periodically
                const interval = setInterval(() => {
                    if (ws.readyState !== WebSocket.OPEN) {
                        clearInterval(interval);
                        return;
                    }
                    
                    const newEvent = {
                        id: `event_${Date.now()}`,
                        pubkey: "dynamic_user",
                        created_at: Math.floor(Date.now() / 1000),
                        kind: 1,
                        tags: [["t", "9q"]],
                        content: `Live message at ${new Date().toLocaleTimeString()}`,
                        sig: "fake_sig_dynamic"
                    };
                    
                    const eventMsg = JSON.stringify(['EVENT', subscription_id, newEvent]);
                    console.log('Sending live event:', newEvent.content);
                    ws.send(eventMsg);
                }, 5000); // Send a new message every 5 seconds
                
            } else if (msg[0] === 'CLOSE') {
                console.log(`Closing subscription ${msg[1]}`);
                // In a real relay, we'd stop sending events for this subscription
            }
            
        } catch (e) {
            console.error('Error processing message:', e);
            const notice = JSON.stringify(['NOTICE', 'Invalid message format']);
            ws.send(notice);
        }
    });
    
    ws.on('close', () => {
        console.log('Client disconnected');
    });
    
    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
    });
});

console.log('Press Ctrl-C to stop the relay');