# Account Deletion App Review Checklist

Manual verification for Apple App Review Guideline 5.1.1(v):

- Log in and open Profile.
- Confirm the Account section shows `계정 삭제` for logged-in users.
- Confirm logged-out users do not see an account deletion request/link in Profile.
- Tap `계정 삭제` and confirm the first Korean warning explains that account-linked data is deleted and cannot be recovered.
- Tap `계정 삭제` on the first warning and confirm the final destructive confirmation appears.
- Confirm final `삭제` sends exactly one authenticated `DELETE /account` request with `Authorization: Bearer {accessToken}`.
- Confirm success shows `계정이 삭제되었습니다.`, clears access token, refresh token, current user, user-scoped local data, exchange connection state, alert state, and push session state.
- Confirm success returns the app to an unauthenticated state and protected screens no longer show deleted account data.
- Confirm failure keeps the current session and shows `계정 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.` or a login-required message for expired sessions.
- Relaunch the app after success and confirm the deleted account is not restored automatically.
