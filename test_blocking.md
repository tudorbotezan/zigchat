# Testing Name-Based Blocking Feature

## How to Use

### Block Spammers by Name Pattern

1. **Block exact name:**
   ```
   /blockname ME
   ```
   This blocks any user with the exact username "ME"

2. **Block pattern with wildcard:**
   ```
   /blockname ME*
   ```
   This blocks any username starting with "ME" (e.g., ME#4b10, ME#7035, etc.)

3. **Block pattern containing text:**
   ```
   /blockname *spam*
   ```
   This blocks any username containing "spam"

### Manage Blocked Names

- **View blocked names:**
  ```
  /blockednames
  ```

- **Unblock a name/pattern:**
  ```
  /unblockname ME*
  ```

### Example for Your Spam Issue

Based on your spam example where users with names like "ME#4b10", "ME#7035", etc. are spamming, you can:

1. Block all "ME" variations:
   ```
   /blockname ME
   ```
   or if they have different suffixes:
   ```
   /blockname ME*
   ```

2. The filter will automatically skip messages from any user whose name matches the blocked pattern, regardless of their changing IDs.

### Persistence

- Blocked names are saved to `~/.zigchat/blocked_names.txt`
- They persist across application restarts
- Works alongside the existing ID-based blocking system

### Combined Blocking

You can use both systems together:
- `/block` for blocking specific user IDs
- `/blockname` for blocking name patterns

This gives you fine-grained control over filtering spam and unwanted messages.