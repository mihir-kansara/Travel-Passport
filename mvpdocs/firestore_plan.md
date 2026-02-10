# Firestore Phase 2 Plan

## Schema

### Trip document
`trips/{tripId}`
- destination, dates, description, audience, members, story headline/highlights
- story.wallStats.likes/comments and story.likedBy (until likes move to subcollection)
- updates/checklists/join requests remain for now

### Itinerary
`trips/{tripId}/itinerary/{itemId}`
- id, tripId, title, type, dateTime, dayKey, manualOrder
- location, link, assignee fields, status, notes
- createdAt, updatedAt (server timestamps) + createdAtClient fallback

### Chat
`trips/{tripId}/messages/{messageId}`
- id, authorId, text
- createdAt, updatedAt (server timestamps) + createdAtClient fallback

### Trip wall comments
`trips/{tripId}/comments/{commentId}`
- id, authorId, text
- createdAt, updatedAt (server timestamps) + createdAtClient fallback

### Itinerary item comments
`trips/{tripId}/itinerary/{itemId}/comments/{commentId}`
- id, authorId, text
- createdAt, updatedAt (server timestamps) + createdAtClient fallback

### Invites
`invites/{token}`

## Migration
- One-time migration on app open for legacy trips:
	- If trip doc has `itinerary`, `chat`, or `story.wallComments` arrays and the corresponding subcollection is empty,
		copy each array into its subcollection, then clear the legacy arrays on the trip doc.
- Fallback read stays in place if subcollections are still empty.

## Notes
- Move large, fast-changing arrays out of the trip document to avoid size growth and write contention.
- Keep trip doc for summary fields only (destination, dates, hero image, audience, story headline/highlights).
- For wall feed, prefer lightweight story summaries (headline/highlights/hero) and lazy-load moments/comments.
- Itinerary ordering: dayKey + time, then manualOrder as a tiebreaker for reorders.
- Chat pagination: load last 50 by default, fetch older pages on demand.
