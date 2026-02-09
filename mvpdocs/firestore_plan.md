# Firestore Phase 2 Plan

## Planned subcollections
- trips/{tripId}/itinerary
- trips/{tripId}/chat
- trips/{tripId}/comments
- trips/{tripId}/checklists
- invites/{token}

## Notes
- Move large, fast-changing arrays out of the trip document to avoid size growth and write contention.
- Keep trip doc for summary fields only (destination, dates, hero image, audience, story headline/highlights).
- For wall feed, prefer lightweight story summaries (headline/highlights/hero) and lazy-load moments/comments.
