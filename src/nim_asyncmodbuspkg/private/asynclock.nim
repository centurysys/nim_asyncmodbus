import std/asyncdispatch

type
  AsyncLock* = ref object
    locked: bool
    waiters: seq[Future[void]]

# ------------------------------------------------------------------------------
# Constructor:
# ------------------------------------------------------------------------------
proc newAsyncLock*(): AsyncLock =
  result = new AsyncLock

# ------------------------------------------------------------------------------
# API:
# ------------------------------------------------------------------------------
proc acquire*(self: AsyncLock): Future[void] =
  result = newFuture[void]("AsyncLock.acquire")
  if not self.locked:
    self.locked = true
    result.complete()
  else:
    self.waiters.add(result)

# ------------------------------------------------------------------------------
# API:
# ------------------------------------------------------------------------------
proc release*(self: AsyncLock) =
  if self.waiters.len > 0:
    let fut = self.waiters[0]
    self.waiters.delete(0)
    if not fut.finished:
      fut.complete()
  else:
    self.locked = false
