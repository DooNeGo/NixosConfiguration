"""The instance of a backend: by name for a new one, from the metadata for a running one."""

import json

from .container import ContainerInstance
from .instance import Host, Instance
from .vm import VmInstance

INSTANCES = {"container": ContainerInstance, "vm": VmInstance}


def make_instance(host: Host, name: str, backend: str, user: str | None = None) -> Instance:
    return INSTANCES[backend](host, name, user)


def open_instance(host: Host, name: str) -> Instance:
    """The instance `name` as it was started; one without metadata (a half-made one) is a container."""
    meta_file = host.state / name / "meta.json"
    meta = json.loads(meta_file.read_text()) if meta_file.is_file() else {}
    return make_instance(host, name, meta.get("backend", "container"), meta.get("user"))
