#!/usr/bin/env python3
"""SQL-backed interactive shell for folder hierarchy (terminal program)."""

from __future__ import annotations

import argparse
import os
import sqlite3
from pathlib import Path


class HierarchyDB:
    def __init__(self, db_path: str) -> None:
        self.db_path = os.path.abspath(db_path)
        parent_dir = os.path.dirname(self.db_path)
        if parent_dir:
            os.makedirs(parent_dir, exist_ok=True)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute("PRAGMA foreign_keys = ON")
        self._init_schema()

    def _init_schema(self) -> None:
        self.conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS sources (
                id INTEGER PRIMARY KEY,
                root_path TEXT NOT NULL UNIQUE,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS nodes (
                id INTEGER PRIMARY KEY,
                source_id INTEGER NOT NULL,
                parent_id INTEGER,
                name TEXT NOT NULL,
                full_path TEXT NOT NULL,
                node_type TEXT NOT NULL CHECK(node_type IN ('dir', 'file')),
                size_bytes INTEGER,
                modified_at REAL,
                FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE CASCADE,
                FOREIGN KEY(parent_id) REFERENCES nodes(id) ON DELETE CASCADE,
                UNIQUE(source_id, full_path)
            );

            CREATE INDEX IF NOT EXISTS idx_nodes_source_parent
                ON nodes(source_id, parent_id, node_type, name);
            """
        )
        self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    def upsert_source(self, root_path: str) -> int:
        root_path = os.path.abspath(root_path)
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO sources(root_path, updated_at)
            VALUES (?, CURRENT_TIMESTAMP)
            ON CONFLICT(root_path)
            DO UPDATE SET updated_at = CURRENT_TIMESTAMP
            """,
            (root_path,),
        )
        self.conn.commit()

        cur.execute("SELECT id FROM sources WHERE root_path = ?", (root_path,))
        row = cur.fetchone()
        if row is None:
            raise RuntimeError("Failed to create source in database")
        return int(row[0])

    def clear_source_nodes(self, source_id: int) -> None:
        self.conn.execute("DELETE FROM nodes WHERE source_id = ?", (source_id,))
        self.conn.commit()

    def sync_source(self, root_path: str, include_files: bool = True) -> tuple[int, int]:
        root_path = os.path.abspath(root_path)
        if not os.path.isdir(root_path):
            raise NotADirectoryError(root_path)

        source_id = self.upsert_source(root_path)
        self.clear_source_nodes(source_id)

        dir_count = 0
        file_count = 0
        cur = self.conn.cursor()

        def insert_node(
            parent_id: int | None,
            name: str,
            full_path: str,
            node_type: str,
            size_bytes: int | None,
            modified_at: float | None,
        ) -> int:
            cur.execute(
                """
                INSERT INTO nodes(source_id, parent_id, name, full_path, node_type, size_bytes, modified_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (source_id, parent_id, name, full_path, node_type, size_bytes, modified_at),
            )
            return int(cur.lastrowid)

        root_name = os.path.basename(root_path) or root_path
        root_stat = os.stat(root_path)
        root_id = insert_node(None, root_name, root_path, "dir", None, root_stat.st_mtime)
        dir_count += 1

        def walk(parent_node_id: int, directory: str) -> None:
            nonlocal dir_count, file_count
            try:
                entries = list(os.scandir(directory))
            except (PermissionError, FileNotFoundError):
                return

            entries.sort(key=lambda e: (not e.is_dir(follow_symlinks=False), e.name.lower()))
            for entry in entries:
                full_path = entry.path
                try:
                    stat = entry.stat(follow_symlinks=False)
                except (PermissionError, FileNotFoundError):
                    continue

                if entry.is_dir(follow_symlinks=False):
                    child_id = insert_node(parent_node_id, entry.name, full_path, "dir", None, stat.st_mtime)
                    dir_count += 1
                    walk(child_id, full_path)
                elif include_files:
                    insert_node(parent_node_id, entry.name, full_path, "file", stat.st_size, stat.st_mtime)
                    file_count += 1

        walk(root_id, root_path)
        self.conn.commit()
        return dir_count, file_count

    def get_root_node(self, root_path: str) -> dict | None:
        root_path = os.path.abspath(root_path)
        cur = self.conn.cursor()
        cur.execute(
            """
            SELECT n.id, n.parent_id, n.name, n.full_path, n.node_type
            FROM nodes n
            JOIN sources s ON s.id = n.source_id
            WHERE s.root_path = ? AND n.parent_id IS NULL
            LIMIT 1
            """,
            (root_path,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        return {
            "id": int(row[0]),
            "parent_id": None,
            "name": str(row[2]),
            "full_path": str(row[3]),
            "node_type": str(row[4]),
        }

    def get_node(self, node_id: int) -> dict | None:
        cur = self.conn.cursor()
        cur.execute(
            """
            SELECT id, parent_id, name, full_path, node_type
            FROM nodes
            WHERE id = ?
            LIMIT 1
            """,
            (node_id,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        return {
            "id": int(row[0]),
            "parent_id": int(row[1]) if row[1] is not None else None,
            "name": str(row[2]),
            "full_path": str(row[3]),
            "node_type": str(row[4]),
        }

    def get_children(self, parent_id: int, show_files: bool) -> list[dict]:
        cur = self.conn.cursor()
        if show_files:
            cur.execute(
                """
                SELECT id, parent_id, name, full_path, node_type
                FROM nodes
                WHERE parent_id = ?
                ORDER BY CASE node_type WHEN 'dir' THEN 0 ELSE 1 END, lower(name)
                """,
                (parent_id,),
            )
        else:
            cur.execute(
                """
                SELECT id, parent_id, name, full_path, node_type
                FROM nodes
                WHERE parent_id = ? AND node_type = 'dir'
                ORDER BY lower(name)
                """,
                (parent_id,),
            )

        rows = cur.fetchall()
        return [
            {
                "id": int(r[0]),
                "parent_id": int(r[1]) if r[1] is not None else None,
                "name": str(r[2]),
                "full_path": str(r[3]),
                "node_type": str(r[4]),
            }
            for r in rows
        ]


class FolderShellSQLProgram:
    def __init__(self, db_path: str, source_path: str, show_files: bool) -> None:
        self.db = HierarchyDB(db_path)
        self.source_path = os.path.abspath(source_path)
        self.show_files = show_files
        self.current_node: dict | None = None

    def sync(self) -> None:
        dir_count, file_count = self.db.sync_source(self.source_path, include_files=True)
        print(f"Synced to SQL: {dir_count} dirs, {file_count} files")
        self.current_node = self.db.get_root_node(self.source_path)

    def ensure_root(self) -> bool:
        root = self.db.get_root_node(self.source_path)
        if root is None:
            print("No SQL data for source. Running first sync...")
            self.sync()
            root = self.db.get_root_node(self.source_path)

        if root is None:
            print("Cannot load root from SQL.")
            return False

        self.current_node = root
        return True

    def print_header(self) -> None:
        print("\nFolder Shell SQL (program mode)")
        print(f"Source: {self.source_path}")
        print(f"DB: {self.db.db_path}")
        print(f"Show files: {'ON' if self.show_files else 'OFF'}")

    def print_help(self) -> None:
        print("\nCommands:")
        print("  [number]   open item by index if it is a directory")
        print("  ..         go to parent directory")
        print("  root       go to root")
        print("  files on   show files")
        print("  files off  hide files")
        print("  sync       rescan source and update SQL")
        print("  source <path>  change source path")
        print("  tree [depth]   print subtree from current node")
        print("  pwd        show current SQL node path")
        print("  help       show this help")
        print("  q          quit")

    def list_current(self) -> list[dict]:
        if self.current_node is None:
            return []
        children = self.db.get_children(self.current_node["id"], self.show_files)
        print(f"\nCurrent: {self.current_node['full_path']}")
        if not children:
            print("  (empty)")
            return children

        for idx, child in enumerate(children, start=1):
            icon = "[D]" if child["node_type"] == "dir" else "[F]"
            print(f"  {idx:>2}. {icon} {child['name']}")
        return children

    def print_tree(self, node_id: int, depth: int, prefix: str = "") -> None:
        node = self.db.get_node(node_id)
        if node is None:
            return

        icon = "[D]" if node["node_type"] == "dir" else "[F]"
        print(f"{prefix}{icon} {node['name']}")
        if depth <= 0 or node["node_type"] != "dir":
            return

        children = self.db.get_children(node_id, self.show_files)
        for child in children:
            self.print_tree(child["id"], depth - 1, prefix + "  ")

    def run(self) -> None:
        if not os.path.isdir(self.source_path):
            raise NotADirectoryError(self.source_path)

        if not self.ensure_root():
            return

        self.print_header()
        self.print_help()

        while True:
            children = self.list_current()
            raw = input("\ncmd> ").strip()
            if not raw:
                continue

            if raw in {"q", "quit", "exit"}:
                break
            if raw == "help":
                self.print_help()
                continue
            if raw == "pwd":
                if self.current_node:
                    print(self.current_node["full_path"])
                continue
            if raw == "root":
                root = self.db.get_root_node(self.source_path)
                if root:
                    self.current_node = root
                continue
            if raw == "..":
                if self.current_node and self.current_node["parent_id"] is not None:
                    parent = self.db.get_node(int(self.current_node["parent_id"]))
                    if parent:
                        self.current_node = parent
                continue
            if raw == "sync":
                self.sync()
                continue
            if raw == "files on":
                self.show_files = True
                continue
            if raw == "files off":
                self.show_files = False
                continue
            if raw.startswith("source "):
                new_source = os.path.abspath(raw[7:].strip())
                if not os.path.isdir(new_source):
                    print(f"Not a directory: {new_source}")
                    continue
                self.source_path = new_source
                self.sync()
                continue
            if raw.startswith("tree"):
                depth = 3
                parts = raw.split()
                if len(parts) > 1:
                    try:
                        depth = max(0, int(parts[1]))
                    except ValueError:
                        print("Depth must be a number")
                        continue
                if self.current_node:
                    print()
                    self.print_tree(self.current_node["id"], depth)
                continue
            if raw.isdigit():
                index = int(raw)
                if index < 1 or index > len(children):
                    print("Invalid index")
                    continue
                selected = children[index - 1]
                if selected["node_type"] != "dir":
                    print("Selected item is a file, not a directory")
                    continue
                self.current_node = selected
                continue

            print("Unknown command. Type 'help'.")

        self.db.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SQL-backed visual shell for folder hierarchy.")
    parser.add_argument(
        "source",
        nargs="?",
        default=os.getcwd(),
        help="Source directory to scan and store in SQL.",
    )
    parser.add_argument(
        "--db",
        default=str(Path.home() / ".local" / "share" / "folder_shell" / "hierarchy.db"),
        help="Path to SQLite database file.",
    )
    parser.add_argument(
        "--dirs-only",
        action="store_true",
        help="Hide files in program listing (files stay stored in SQL).",
    )
    parser.add_argument(
        "--sync-first",
        action="store_true",
        help="Force sync before opening shell.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    app = FolderShellSQLProgram(
        db_path=args.db,
        source_path=args.source,
        show_files=not args.dirs_only,
    )
    if args.sync_first:
        app.sync()
    app.run()


if __name__ == "__main__":
    main()
