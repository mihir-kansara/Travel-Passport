# QA Checklist - Travel Passport

## Auth
- [ ] Google sign-in works
- [ ] Apple sign-in does not crash on Android
- [ ] Anonymous/dev login works (if enabled)
- [ ] Session gate does not loop

## Navigation
- [ ] Bottom nav tabs switch correctly
- [ ] Back navigation works on pushed screens
- [ ] Home icon returns to root from deep screens

## Trips
- [ ] Create trip flow (2 steps) works
- [ ] Destination typeahead selection works
- [ ] Edit trip settings save correctly
- [ ] Publish/unpublish to wall works
- [ ] Trip detail tabs are accessible

## Invites
- [ ] Invite link is created and copied
- [ ] Manual token join works
- [ ] Invalid token shows error
- [ ] Joining adds membership and refreshes providers

## Planner
- [ ] Day switching works
- [ ] Add item via bottom sheet works
- [ ] Edit item works
- [ ] Delete item works
- [ ] Sections show correctly (Flights/Stay/Food/Activities/Other/Notes)
- [ ] Timeline ordering (time then order)

## Checklist
- [ ] Member checklist toggles save
- [ ] Owner can toggle others
- [ ] Shared checklist add/toggle/delete works
- [ ] Checklist persists in Firestore

## Story / Wall
- [ ] Published trips show on wall
- [ ] Story detail loads
- [ ] Likes/comments update UI
