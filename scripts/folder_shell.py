#!/usr/bin/env python3
"""Simple desktop shell to visualize folder hierarchy."""

from __future__ import annotations

import argparse
import os
import tkinter as tk
from tkinter import filedialog, ttk

DUMMY_NODE = "__dummy__"


class FolderShell(tk.Tk):
    def __init__(self, root_path: str, show_files: bool) -> None:
        super().__init__()
        self.title("Folder Shell")
        self.geometry("1000x650")
        self.minsize(720, 480)

        self.root_path = os.path.abspath(root_path)
        self.show_files_var = tk.BooleanVar(value=show_files)
        self.path_to_node: dict[str, str] = {}

        self._build_ui()
        self._load_root()

    def _build_ui(self) -> None:
        top = ttk.Frame(self, padding=10)
        top.pack(fill="x")

        ttk.Label(top, text="Root:").pack(side="left")

        self.path_var = tk.StringVar(value=self.root_path)
        self.path_entry = ttk.Entry(top, textvariable=self.path_var)
        self.path_entry.pack(side="left", fill="x", expand=True, padx=(8, 8))

        ttk.Button(top, text="Browse", command=self._browse_root).pack(side="left")
        ttk.Button(top, text="Reload", command=self._reload).pack(side="left", padx=(8, 0))

        ttk.Checkbutton(
            top,
            text="Show files",
            variable=self.show_files_var,
            command=self._reload,
        ).pack(side="left", padx=(14, 0))

        main = ttk.Frame(self, padding=(10, 0, 10, 10))
        main.pack(fill="both", expand=True)

        self.tree = ttk.Treeview(main, columns=("type", "path"), show="tree headings")
        self.tree.heading("#0", text="Name", anchor="w")
        self.tree.heading("type", text="Type", anchor="w")
        self.tree.heading("path", text="Path", anchor="w")
        self.tree.column("#0", width=350, stretch=True)
        self.tree.column("type", width=90, stretch=False)
        self.tree.column("path", width=520, stretch=True)

        yscroll = ttk.Scrollbar(main, orient="vertical", command=self.tree.yview)
        xscroll = ttk.Scrollbar(main, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=yscroll.set, xscrollcommand=xscroll.set)

        self.tree.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        xscroll.grid(row=1, column=0, sticky="ew")

        main.columnconfigure(0, weight=1)
        main.rowconfigure(0, weight=1)

        self.tree.bind("<<TreeviewOpen>>", self._on_open)
        self.tree.bind("<<TreeviewSelect>>", self._on_select)

        self.status_var = tk.StringVar(value="Ready")
        status = ttk.Label(self, textvariable=self.status_var, anchor="w", padding=10)
        status.pack(fill="x")

    def _set_status(self, text: str) -> None:
        self.status_var.set(text)

    def _browse_root(self) -> None:
        selected = filedialog.askdirectory(initialdir=self.root_path)
        if not selected:
            return
        self.path_var.set(selected)
        self._reload()

    def _reload(self) -> None:
        chosen = self.path_var.get().strip()
        if not chosen:
            self._set_status("Root path is empty")
            return

        chosen = os.path.abspath(chosen)
        if not os.path.isdir(chosen):
            self._set_status(f"Not a directory: {chosen}")
            return

        self.root_path = chosen
        self._load_root()

    def _load_root(self) -> None:
        self.tree.delete(*self.tree.get_children())
        self.path_to_node.clear()

        label = os.path.basename(self.root_path) or self.root_path
        root_node = self.tree.insert(
            "",
            "end",
            text=label,
            values=("dir", self.root_path),
            open=True,
        )
        self.path_to_node[self.root_path] = root_node
        self._add_dummy(root_node)
        self._populate_children(root_node, self.root_path)
        self._set_status(f"Loaded: {self.root_path}")

    def _add_dummy(self, node: str) -> None:
        self.tree.insert(node, "end", iid=f"{node}:{DUMMY_NODE}", text="...")

    def _remove_dummy(self, node: str) -> None:
        for child in self.tree.get_children(node):
            if child.endswith(f":{DUMMY_NODE}"):
                self.tree.delete(child)

    def _has_dummy(self, node: str) -> bool:
        return any(child.endswith(f":{DUMMY_NODE}") for child in self.tree.get_children(node))

    def _on_open(self, _event: tk.Event) -> None:
        selected = self.tree.focus()
        if not selected:
            return

        values = self.tree.item(selected, "values")
        if not values:
            return

        node_type = values[0]
        node_path = values[1]
        if node_type != "dir":
            return

        if self._has_dummy(selected):
            self._populate_children(selected, node_path)

    def _on_select(self, _event: tk.Event) -> None:
        selected = self.tree.focus()
        if not selected:
            return
        values = self.tree.item(selected, "values")
        if not values:
            return
        self._set_status(values[1])

    def _populate_children(self, parent_node: str, parent_path: str) -> None:
        self._remove_dummy(parent_node)

        try:
            entries = list(os.scandir(parent_path))
        except PermissionError:
            self.tree.insert(parent_node, "end", text="<permission denied>", values=("error", parent_path))
            return
        except FileNotFoundError:
            self.tree.insert(parent_node, "end", text="<not found>", values=("error", parent_path))
            return

        entries.sort(key=lambda e: (not e.is_dir(follow_symlinks=False), e.name.lower()))

        for entry in entries:
            full_path = entry.path
            if entry.is_dir(follow_symlinks=False):
                node = self.tree.insert(
                    parent_node,
                    "end",
                    text=entry.name,
                    values=("dir", full_path),
                )
                self._add_dummy(node)
                self.path_to_node[full_path] = node
            elif self.show_files_var.get():
                self.tree.insert(
                    parent_node,
                    "end",
                    text=entry.name,
                    values=("file", full_path),
                )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Visual shell for folder hierarchy.")
    parser.add_argument(
        "root",
        nargs="?",
        default=os.getcwd(),
        help="Root directory to visualize (defaults to current directory).",
    )
    parser.add_argument(
        "--dirs-only",
        action="store_true",
        help="Start with directories only (files hidden).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    app = FolderShell(root_path=args.root, show_files=not args.dirs_only)
    app.mainloop()


if __name__ == "__main__":
    main()
