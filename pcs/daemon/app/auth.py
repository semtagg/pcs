import base64
import binascii
import logging
import pwd
import socket
import struct
from typing import (
    Optional,
    TypedDict,
    cast,
)

from tornado.http1connection import HTTP1Connection
from tornado.ioloop import IOLoop
from tornado.web import (
    HTTPError,
    RequestHandler,
)

from pcs.daemon.session import (
    Session,
    Storage,
)
from pcs.lib.auth.const import SUPERUSER
from pcs.lib.auth.provider import AuthProvider
from pcs.lib.auth.tools import (
    DesiredUser,
    get_effective_user,
)
from pcs.lib.auth.types import AuthUser

from .common import (
    LegacyApiBaseHandler,
    LegacyApiHandler,
    RoutesType,
)

PCSD_SESSION = "pcsd.sid"


class NotAuthorizedException(Exception):
    pass


class _BaseLibAuthProvider:
    def __init__(
        self, handler: RequestHandler, auth_provider: AuthProvider
    ) -> None:
        self._auth_provider = auth_provider
        self._handler = handler
        self._auth_logger = logging.getLogger("pcs.daemon.auth")

    async def login_user(self, username: str) -> AuthUser:
        auth_user = await IOLoop.current().run_in_executor(
            executor=None,
            func=lambda: self._auth_provider.login_user(username),
        )
        if auth_user is None:
            raise NotAuthorizedException()
        return auth_user

    def is_unix_socket_used(self) -> bool:
        # For whatever reason, handler.request.connection is typed as
        # HTTPConnection in tornado. That class, however, doesn't have stream
        # attribute. In reality, HTTP1Connection is probably used.
        return (
            cast(
                HTTP1Connection, self._handler.request.connection
            ).stream.socket.family
            == socket.AF_UNIX
        )

    def get_unix_socket_user(self) -> Optional[str]:
        if not self.is_unix_socket_used():
            return None

        # It is not cached to prevent inapropriate cache when handler is (in
        # hypotetical future) somehow reused. The responsibility for cache is
        # left to the place, that uses it.
        # For whatever reason, handler.request.connection is typed as
        # HTTPConnection in tornado. That class, however, doesn't have stream
        # attribute. In reality, HTTP1Connection is probably used.
        credentials = cast(
            HTTP1Connection, self._handler.request.connection
        ).stream.socket.getsockopt(
            socket.SOL_SOCKET,
            socket.SO_PEERCRED,
            struct.calcsize("3i"),
        )
        dummy_pid, uid, dummy_gid = struct.unpack("3i", credentials)
        if uid == 0:
            # treat root as cluster superuser
            return SUPERUSER

        return pwd.getpwuid(uid).pw_name

    async def auth_by_socket_user(self) -> AuthUser:
        username = self.get_unix_socket_user()
        if username:
            auth_user = await self.login_user(username)
            if auth_user:
                return auth_user
        raise NotAuthorizedException()


class PasswordAuthProvider(_BaseLibAuthProvider):
    async def auth_by_username_password(
        self, username: str, password: str
    ) -> AuthUser:
        auth_user = await IOLoop.current().run_in_executor(
            executor=None,
            func=lambda: self._auth_provider.auth_by_username_password(
                username, password
            ),
        )
        if auth_user is None:
            raise NotAuthorizedException()
        return auth_user


class TokenAuthProvider(_BaseLibAuthProvider):
    async def auth_by_token(self) -> AuthUser:
        token = self.auth_token
        if token:
            return await self._auth_by_token(token)
        return await self.auth_by_socket_user()

    async def _auth_by_token(self, token: str) -> AuthUser:
        auth_user = await IOLoop.current().run_in_executor(
            executor=None,
            func=lambda: self._auth_provider.auth_by_token(token),
        )
        if auth_user is None:
            raise NotAuthorizedException()
        return auth_user

    async def create_token(self, user: AuthUser) -> Optional[str]:
        return await IOLoop.current().run_in_executor(
            executor=None,
            func=lambda: self._auth_provider.create_token(user.username),
        )

    @property
    def auth_token(self) -> Optional[str]:
        return self._handler.get_cookie("token", default=None)


class LegacyTokenAuthProvider(TokenAuthProvider):
    async def auth_by_token_effective_user(self) -> tuple[AuthUser, AuthUser]:
        real_user = await self.auth_by_token()
        self._auth_logger.debug(
            "Real user=%s groups=%s",
            real_user.username,
            ",".join(real_user.groups),
        )
        if not real_user.is_superuser:
            return real_user, real_user
        effective_user = get_effective_user(
            real_user, self._get_effective_user()
        )
        self._auth_logger.debug(
            "Effective user=%s groups=%s",
            effective_user.username,
            ",".join(effective_user.groups),
        )
        return real_user, effective_user

    def _get_effective_user(self) -> DesiredUser:
        username = self._handler.get_cookie("CIB_user")
        groups = []
        if username:
            # use groups only if user is specified as well
            groups_raw = self._handler.get_cookie("CIB_user_groups")
            if groups_raw:
                try:
                    groups = (
                        base64.b64decode(groups_raw).decode("utf-8").split(" ")
                    )
                except (UnicodeError, binascii.Error):
                    self._auth_logger.warning("Unable to decode users groups")
        return DesiredUser(username, groups)


class SessionAuthProvider(_BaseLibAuthProvider):
    class CookieOptions(TypedDict):
        secure: bool
        httponly: bool
        samesite: str

    __cookie_options: CookieOptions = {
        "secure": True,
        "httponly": True,
        # rhbz#2097393
        # Prevent a cookie to be sent on cross-site requests, allow it to be
        # sent when navigating to pcs web UI from an external site.
        "samesite": "Lax",
    }

    def __init__(
        self,
        handler: RequestHandler,
        auth_provider: AuthProvider,
        session_storage: Storage,
    ) -> None:
        super().__init__(handler, auth_provider)
        self.__session_storage = session_storage
        self.__session: Optional[Session] = None

    def init_session(self) -> None:
        self.__session = self._get_session()

    async def auth_by_sid(self) -> AuthUser:
        if self.__session:
            return await self.login_user(self.__session.username)
        return await self.auth_by_socket_user()

    def _get_session(self) -> Optional[Session]:
        if self.__sid_from_client is None:
            return None
        return self.__session_storage.get(self.__sid_from_client)

    def session_logout(self) -> None:
        if self.__session is not None:
            self.__session_storage.destroy(self.__session.sid)
        self.__session = None
        self._sid_to_cookies()

    def _sid_to_cookies(self) -> None:
        """
        Write the session id into a response cookie.
        """
        if self.__session:
            self._handler.set_cookie(
                PCSD_SESSION, self.__session.sid, **self.__cookie_options
            )
        else:
            self._handler.clear_cookie(PCSD_SESSION)

    def put_request_cookies_sid_to_response_cookies_sid(self) -> None:
        """
        If sid came in the request cookies put it into response cookies. But do
        not start new one.
        """
        # TODO this method should exist temporarily (for sinatra compatibility)
        # pylint: disable=invalid-name
        if self.__sid_from_client is not None:
            self._handler.set_cookie(
                PCSD_SESSION, self.__sid_from_client, **self.__cookie_options
            )

    def is_sid_in_request_cookies(self) -> bool:
        return self.__sid_from_client is not None

    @property
    def __sid_from_client(self) -> Optional[str]:
        return self._handler.get_cookie(PCSD_SESSION, default=None)

    def update_session(self, auth_user: Optional[AuthUser]) -> None:
        if auth_user:
            if (
                not self.__session
                or self.__session.username != auth_user.username
            ):
                self.__session = self.__session_storage.login(
                    auth_user.username
                )
        else:
            self.__session = None
        self._sid_to_cookies()


class LegacyAuth(LegacyApiBaseHandler):
    _password_auth_provider: PasswordAuthProvider
    _token_auth_provider: TokenAuthProvider

    def initialize(self, auth_provider: AuthProvider) -> None:
        super().initialize()
        self._password_auth_provider = PasswordAuthProvider(self, auth_provider)
        self._token_auth_provider = TokenAuthProvider(self, auth_provider)

    async def auth(self) -> None:
        try:
            auth_user = (
                await self._password_auth_provider.auth_by_username_password(
                    self.get_body_argument("username") or "",
                    self.get_body_argument("password") or "",
                )
            )
            token = await self._token_auth_provider.create_token(auth_user)
            if token:
                self.write(token)
            else:
                raise HTTPError(400, reason="Unable to store token")
        except NotAuthorizedException:
            # To stay backward compatible with original ruby implementation,
            # an empty response needs to be returned if authentication fails
            pass

    async def post(self) -> None:
        await self.auth()

    async def get(self) -> None:
        await self.auth()


class LegacyTokenAuthenticationHandler(LegacyApiHandler):
    _token_auth_provider: LegacyTokenAuthProvider
    _auth_user: Optional[AuthUser]

    def initialize(self, auth_provider: AuthProvider) -> None:
        super().initialize()
        self._token_auth_provider = LegacyTokenAuthProvider(self, auth_provider)

    async def prepare(self) -> None:
        # pylint: disable=invalid-overridden-method
        super().prepare()
        try:
            (
                _,
                self._auth_user,
            ) = await self._token_auth_provider.auth_by_token_effective_user()
        except NotAuthorizedException as e:
            raise self.unauthorized() from e

    @property
    def auth_user(self) -> AuthUser:
        if not self._auth_user:
            raise self.unauthorized()
        return self._auth_user

    async def _handle_request(self) -> None:
        raise NotImplementedError()


class CheckAuth(LegacyTokenAuthenticationHandler):
    async def _handle_request(self) -> None:
        self.write('{"success":true}')


def get_routes(
    auth_provider: AuthProvider,
) -> RoutesType:
    auth_payload = dict(auth_provider=auth_provider)
    return [
        ("/remote/auth", LegacyAuth, auth_payload),
        ("/remote/check_auth", CheckAuth, auth_payload),
    ]
