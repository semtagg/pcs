import re
from typing import (
    List,
    Optional,
    Union,
)

from pcs.common import reports
from pcs.common.reports.item import (
    ReportItem,
    ReportItemList,
)
from pcs.common.tools import timeout_to_seconds
from pcs.lib.errors import LibraryError

_BOOLEAN_TRUE = frozenset(["true", "on", "yes", "y", "1"])
_BOOLEAN_FALSE = frozenset(["false", "off", "no", "n", "0"])
BOOLEAN_VALUES = _BOOLEAN_TRUE | _BOOLEAN_FALSE
_ID_FIRST_CHAR_NOT_RE = re.compile("[^a-zA-Z_]")
_ID_REST_CHARS_NOT_RE = re.compile("[^a-zA-Z0-9_.-]")
SCORE_INFINITY = "INFINITY"


def is_boolean(val) -> bool:
    """
    Does pacemaker consider a value to be a boolean?
    See crm_is_true in pacemaker/lib/common/utils.c
    val checked value
    """
    return val.lower() in BOOLEAN_VALUES


def is_true(val) -> bool:
    """
    Does pacemaker consider a value to be true?
    See crm_is_true in pacemaker/lib/common/utils.c
    var checked value
    """
    return val.lower() in _BOOLEAN_TRUE


def is_false(val) -> bool:
    """
    Does pacemaker consider a value to be false?
    See crm_is_true in pacemaker/lib/common/utils.c
    var checked value
    """
    return val.lower() in _BOOLEAN_FALSE


def is_score(value: str) -> bool:
    if not value:
        return False
    unsigned_value = value[1:] if value[0] in ("+", "-") else value
    return unsigned_value == SCORE_INFINITY or unsigned_value.isdigit()


def get_valid_timeout_seconds(
    timeout_candidate: Union[str, int, None],
) -> Optional[int]:
    """
    Transform pacemaker style timeout to number of seconds, raise LibraryError
        on invalid timeout
    timeout_candidate timeout string or None
    """
    if timeout_candidate is None:
        return None
    wait_timeout = timeout_to_seconds(timeout_candidate)
    if wait_timeout is None:
        raise LibraryError(
            ReportItem.error(
                reports.messages.InvalidTimeoutValue(str(timeout_candidate))
            )
        )
    return wait_timeout


def validate_id(
    id_candidate: str,
    description: Optional[str] = None,
    reporter: Union[None, List, ReportItemList] = None,
):
    """
    Validate a pacemaker id, raise LibraryError on invalid id.

    id_candidate id's value
    description id's role description (default "id")
    """
    # see NCName definition
    # http://www.w3.org/TR/REC-xml-names/#NT-NCName
    # http://www.w3.org/TR/REC-xml/#NT-Name
    description = "id" if not description else description  # for mypy
    if not id_candidate:
        report_item = ReportItem.error(
            reports.messages.InvalidIdIsEmpty(description)
        )
        if reporter is None:
            # we check for None so it works with an empty list as well
            raise LibraryError(report_item)
        reporter.append(report_item)
        return
    if _ID_FIRST_CHAR_NOT_RE.match(id_candidate[0]):
        report_item = ReportItem.error(
            reports.messages.InvalidIdBadChar(
                id_candidate,
                description,
                id_candidate[0],
                True,
            )
        )
        if reporter is not None:
            reporter.append(report_item)
        else:
            raise LibraryError(report_item)
    for char in id_candidate[1:]:
        if _ID_REST_CHARS_NOT_RE.match(char):
            report_item = ReportItem.error(
                reports.messages.InvalidIdBadChar(
                    id_candidate,
                    description,
                    char,
                    False,
                )
            )
            if reporter is not None:
                reporter.append(report_item)
            else:
                raise LibraryError(report_item)


def sanitize_id(id_candidate, replacement=""):
    if not id_candidate:
        return id_candidate
    return "".join(
        [
            ""
            if _ID_FIRST_CHAR_NOT_RE.match(id_candidate[0])
            else id_candidate[0],
            _ID_REST_CHARS_NOT_RE.sub(replacement, id_candidate[1:]),
        ]
    )
