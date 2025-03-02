# pylint: disable=protected-access
from datetime import timedelta
from unittest import (
    TestCase,
    mock,
)

import pcs.daemon.async_tasks.task as tasks
from pcs.common.async_tasks import types
from pcs.common.async_tasks.dto import (
    CommandDto,
    CommandOptionsDto,
)
from pcs.common.reports import ReportItemDto
from pcs.daemon.async_tasks.types import Command
from pcs.daemon.async_tasks.worker.types import (
    Message,
    TaskExecuted,
    TaskFinished,
)
from pcs.settings import (
    task_abandoned_timeout_seconds,
    task_unresponsive_timeout_seconds,
)

from .helpers import (
    AUTH_USER,
    DATETIME_NOW,
    MockDateTimeNowMixin,
    MockOsKillMixin,
)

TASK_IDENT = "id0"
TEST_TIMEOUT_S = 10
DATETIME_BEFORE_TIMEOUT = DATETIME_NOW - timedelta(seconds=TEST_TIMEOUT_S / 2)
DATETIME_AFTER_TIMEOUT = DATETIME_NOW - timedelta(seconds=TEST_TIMEOUT_S + 1)
WORKER_PID = 2222


class TaskBaseTestCase(TestCase):
    def setUp(self):
        self.task = tasks.Task(
            TASK_IDENT,
            Command(
                CommandDto(
                    "command", {}, CommandOptionsDto(request_timeout=None)
                )
            ),
            AUTH_USER,
            tasks.TaskConfig(),
        )


class TestReceiveMessage(MockDateTimeNowMixin, TaskBaseTestCase):
    def setUp(self):
        super().setUp()
        self.mock_datetime_now = self._init_mock_datetime_now()

    def test_report(self):
        payload = mock.MagicMock(ReportItemDto)
        message = Message(TASK_IDENT, payload)
        self.task.receive_message(message)
        self.assertEqual([payload], self.task.to_dto().reports)
        self.assertEqual(DATETIME_NOW, self.task._last_message_at)
        self.mock_datetime_now.assert_called_once()

    def test_task_executed(self):
        message = Message(TASK_IDENT, TaskExecuted(WORKER_PID))
        self.task.receive_message(message)
        self.assertEqual(types.TaskState.EXECUTED, self.task.state)
        self.assertEqual(WORKER_PID, self.task._worker_pid)
        self.assertEqual(DATETIME_NOW, self.task._last_message_at)
        self.mock_datetime_now.assert_called()

    def test_task_finished(self):
        message = Message(
            TASK_IDENT,
            TaskFinished(types.TaskFinishType.SUCCESS, "result"),
        )
        self.task.receive_message(message)
        task_dto = self.task.to_dto()
        self.assertEqual(types.TaskState.FINISHED, task_dto.state)
        self.assertEqual(
            types.TaskFinishType.SUCCESS, task_dto.task_finish_type
        )
        self.assertEqual("result", task_dto.result)
        self.assertEqual(DATETIME_NOW, self.task._last_message_at)
        self.mock_datetime_now.assert_called_once()

    def test_unsupported_message_type(self):
        message = Message(TASK_IDENT, 3)
        with self.assertRaises(tasks.UnknownMessageError) as thrown_exc:
            self.task.receive_message(message)
        self.assertEqual(type(3).__name__, thrown_exc.exception.payload_type)
        self.mock_datetime_now.assert_not_called()


class TestRequestKill(TaskBaseTestCase):
    def test_kill_requested(self):
        self.task.request_kill(types.TaskKillReason.USER)
        self.assertEqual(
            types.TaskKillReason.USER, self.task.to_dto().kill_reason
        )
        self.assertTrue(self.task.is_kill_requested())

    def test_kill_not_requested(self):
        self.assertFalse(self.task.is_kill_requested())


class TestKill(MockOsKillMixin, TaskBaseTestCase):
    def setUp(self):
        super().setUp()
        self.mock_os_kill = self._init_mock_os_kill()

    def _assert_killed(self, start_state):
        if self.task.state != start_state:
            self.task.state = start_state
        self.task.kill()
        task_dto = self.task.to_dto()
        self.mock_os_kill.assert_not_called()
        self.assertEqual(types.TaskState.FINISHED, task_dto.state)
        self.assertEqual(types.TaskFinishType.KILL, task_dto.task_finish_type)

    def _assert_not_killed(self, start_state):
        finish_type = self.task.to_dto().task_finish_type
        self.task.state = start_state
        self.task.kill()
        task_dto = self.task.to_dto()
        self.mock_os_kill.assert_not_called()
        self.assertEqual(start_state, task_dto.state)
        self.assertEqual(finish_type, task_dto.task_finish_type)

    def test_kill_created(self):
        self._assert_killed(types.TaskState.CREATED)

    def test_kill_queued(self):
        self._assert_not_killed(types.TaskState.QUEUED)

    def test_kill_executed_worker_alive(self):
        message = Message(TASK_IDENT, TaskExecuted(WORKER_PID))
        self.task.receive_message(message)
        self.task.kill()
        task_dto = self.task.to_dto()
        self.mock_os_kill.assert_called_once_with(WORKER_PID, 15)
        self.assertEqual(types.TaskState.FINISHED, task_dto.state)
        self.assertEqual(types.TaskFinishType.KILL, task_dto.task_finish_type)

    def test_kill_executed_worker_dead(self):
        message = Message(TASK_IDENT, TaskExecuted(WORKER_PID))
        self.task.receive_message(message)
        self.mock_os_kill.raiseError.side_effect = ProcessLookupError()
        self.task.kill()
        task_dto = self.task.to_dto()
        self.mock_os_kill.assert_called_once_with(WORKER_PID, 15)
        self.assertEqual(types.TaskState.FINISHED, task_dto.state)
        self.assertEqual(types.TaskFinishType.KILL, task_dto.task_finish_type)

    def test_kill_finished(self):
        self._assert_not_killed(types.TaskState.FINISHED)


class TestGetLastTimestamp(MockDateTimeNowMixin, TaskBaseTestCase):
    def test_no_messages_created(self):
        self.assertIsNone(self.task._get_last_updated_timestamp())

    def test_no_messages_queued(self):
        self.task.state = types.TaskState.QUEUED
        self.assertIsNone(self.task._get_last_updated_timestamp())

    def test_no_messages_executed(self):
        # This can't happen - task is switched to executed by receiving
        # a TaskExecuted message
        pass

    def test_no_messages_finished(self):
        # This can happen when Task is killed in created state
        self.task.state = types.TaskState.FINISHED
        self._init_mock_datetime_now()
        self.assertEqual(DATETIME_NOW, self.task._get_last_updated_timestamp())
        self.assertEqual(DATETIME_NOW, self.task._last_message_at)

    # There can't be created or queued tasks that have messages, task is
    # assigned to a worker (which sends messages) in executed state
    def test_created(self):
        pass

    def test_queued(self):
        pass

    def test_executed(self):
        self._init_mock_datetime_now()
        message = Message(TASK_IDENT, TaskExecuted(WORKER_PID))
        self.task.receive_message(message)
        self.assertEqual(DATETIME_NOW, self.task._get_last_updated_timestamp())

    def test_finished(self):
        self._init_mock_datetime_now()
        message = Message(
            TASK_IDENT, TaskFinished(types.TaskFinishType.FAIL, None)
        )
        self.task.receive_message(message)
        self.assertEqual(DATETIME_NOW, self.task._get_last_updated_timestamp())


@mock.patch.object(tasks.Task, "_get_last_updated_timestamp")
class TestIsTimedOut(MockDateTimeNowMixin, TaskBaseTestCase):
    def setUp(self):
        super().setUp()
        self._init_mock_datetime_now()  # assertions not needed

    def test_not_timed_out(self, mock_last_timestamp):
        mock_last_timestamp.return_value = DATETIME_BEFORE_TIMEOUT
        self.assertFalse(self.task._is_timed_out(TEST_TIMEOUT_S))
        mock_last_timestamp.assert_called_once()

    def test_timed_out(self, mock_last_timestamp):
        mock_last_timestamp.return_value = DATETIME_AFTER_TIMEOUT
        self.assertTrue(self.task._is_timed_out(TEST_TIMEOUT_S))
        mock_last_timestamp.assert_called_once()


@mock.patch.object(tasks.Task, "_is_timed_out")
class TestDefunct(TaskBaseTestCase):
    def _assert_not_defunct(self, mock_is_timed_out, state):
        if self.task.state != state:
            self.task.state = state
        self.assertFalse(self.task.is_defunct())
        mock_is_timed_out.assert_not_called()

    def test_not_defunct_created(self, mock_is_timed_out):
        self._assert_not_defunct(mock_is_timed_out, types.TaskState.CREATED)

    def test_not_defunct_queued(self, mock_is_timed_out):
        self._assert_not_defunct(mock_is_timed_out, types.TaskState.QUEUED)

    def test_not_defunct_executed(self, mock_is_timed_out):
        self.task.state = types.TaskState.EXECUTED
        mock_is_timed_out.return_value = False
        self.assertFalse(self.task.is_defunct())
        mock_is_timed_out.assert_called_once_with(
            task_unresponsive_timeout_seconds
        )

    def test_defunct_executed(self, mock_is_timed_out):
        self.task.state = types.TaskState.EXECUTED
        mock_is_timed_out.return_value = True
        self.assertTrue(self.task.is_defunct())
        mock_is_timed_out.assert_called_once_with(
            task_unresponsive_timeout_seconds
        )

    def test_not_defunct_finished(self, mock_is_timed_out):
        self._assert_not_defunct(mock_is_timed_out, types.TaskState.FINISHED)


@mock.patch.object(tasks.Task, "_is_timed_out")
class TestAbandoned(TaskBaseTestCase):
    def _assert_not_abandoned(self, mock_is_timed_out, state):
        if self.task.state != state:
            self.task.state = state
        self.assertFalse(self.task.is_abandoned())
        mock_is_timed_out.assert_not_called()

    def test_not_abandoned_created(self, mock_is_timed_out):
        self._assert_not_abandoned(mock_is_timed_out, types.TaskState.CREATED)

    def test_not_abandoned_queued(self, mock_is_timed_out):
        self._assert_not_abandoned(mock_is_timed_out, types.TaskState.QUEUED)

    def test_not_abandoned_executed(self, mock_is_timed_out):
        self._assert_not_abandoned(mock_is_timed_out, types.TaskState.EXECUTED)

    def test_abandoned_finished(self, mock_is_timed_out):
        self.task.state = types.TaskState.FINISHED
        mock_is_timed_out.return_value = True
        self.assertTrue(self.task.is_abandoned())
        mock_is_timed_out.assert_called_once_with(
            task_abandoned_timeout_seconds
        )

    def test_not_abandoned_finished(self, mock_is_timed_out):
        self.task.state = types.TaskState.FINISHED
        mock_is_timed_out.return_value = False
        self.assertFalse(self.task.is_abandoned())
        mock_is_timed_out.assert_called_once_with(
            task_abandoned_timeout_seconds
        )
