# Folder access diagnostics

These logs measure the first grid open after a folder is allowed. They do not change what GridBack draws, and they never include a path, a user name, or a home folder.

## Reproduce

The picture for this check is a wallpaper in Downloads.

1. Start the log and leave it running:

```
log stream --level info --predicate 'subsystem == "com.jimmythefallony.GridBack"'
```

2. Reset the saved answer and the system folder permission:

```
./scripts/reset-folder-ask.sh
```

3. Open GridBack. In Settings choose Allow…, then Continue, then Don't Allow on the system prompt.
4. In System Settings > Files & Folders, turn GridBack's Downloads switch on.
5. Come back to GridBack. Settings should say Allowed.
6. Open the grid at once. Leave it up long enough to see the background, then close it.
7. Open the grid again about a second later.

## Reading the lines

Every diagnostic line starts with `ms`, the milliseconds since GridBack launched. Place names are words such as Downloads and Desktop. `identity`, `gridHash`, `probeHash`, and `pathHash` are short hashes, not paths.

`grid open` is one line each time the grid opens. `n` is that open's number.

- `asked`, `granted`, and `refused` are 1 when the place is on that list, and 0 when it is not. Refused is the denied list.
- `decision` is the folder policy before a later look changes it: `tryRead`, `offerAsk`, `fallback`, `doNotTouch`, or `none`.
- `exists` and `readable` are fileExists and isReadableFile. 1 is yes, 0 is no, and -1 means that check did not run.
- `images` is the metadata image count, or -1 if metadata was not read.
- `kind` is the identity that was chosen: `file`, `protected`, `neutral`, `unreadable`, or `plain`. A solid colour is `plain`.
- `identity` hashes the cache identity. The same picture keeps the same number for this launch.
- `cache` is `hit` or `miss`.
- `inflight` is 1 when a render of that same identity was already running. `inflightIdentity` is the hash of whatever render was running, or -1 if none was.

`grid read` is the same 16-byte read Settings uses. It runs only when the place is already Allowed, on the path the grid chose, and off the main thread, so it cannot raise a prompt. There is no `grid read` line when the place is not Allowed. `read=ok` with `errno=0` means the bytes were read. Any other `errno` is the error number, and -1 means that shared read did not open the file. `same=1` means the Settings probe and the grid hashed the same path. `haveProbe=0` means Settings has not finished a probe in this launch, so `probeHash` is 0.

`render start` and `render finish` use that same `identity` number. `result` is `success` or `nil`. `duration` is the render time in milliseconds. `errno` is the read error when the picture could not be opened, and 0 otherwise.

`present` is the choice after a render finishes. `outcome` is `ignore`, `plainBlur`, or `picture`. `scheduledOpen` is the open that started the render, and `currentOpen` is the open now. The two identity numbers are the render's and the grid's.

`settings probe` is category `settings`. It is written when the Settings read finishes. `ms` is that completion time. `result` is `granted` or `denied`. `pathHash` is the probe's path hash. `prewarm=1` means that success started a blur for the next open.

On a grey first open, compare that open's `kind`, `cache`, `inflight`, and `identity` with the `render finish` and `present` lines that follow, and with `grid read`. An open that shows the blur at once should have `cache=hit` and the same `identity` as a render that already succeeded.
