def sha256 [path: string] {
  try {
    ^sha256sum -- $path
      | str trim
      | split row " "
      | get 0
  } catch {
    ^shasum -a 256 -- $path
      | str trim
      | split row " "
      | get 0
  }
}

def write_github_output [key: string, value: string] {
  let out = $env.GITHUB_OUTPUT?
  if $out == null {
    return
  }

  $"($key)=($value)\n" | save -a $out
}

def ensure_empty_dir [dir: string] {
  if ($dir | path exists) {
    rm -rf $dir
  }

  mkdir $dir
}

def now_utc_timestamp [] {
  date now | date to-timezone UTC | format date "%Y-%m-%dT%H:%M:%SZ"
}

def update_db [dbdir: string] {
  mkdir $dbdir
  ^cvd config set --dbdir $dbdir
  ^cvd update
}

def list_db_files [dbdir: string] {
  (glob ($dbdir | path join "*.cvd"))
    | append (glob ($dbdir | path join "*.cld"))
    | sort
}

def unpack_db_file [cvd_path: string, unpack_dir: string] {
  let base = ($cvd_path | path basename)
  let name = ($base | str replace -r "\\.(cvd|cld)$" "")
  let dst_dir = ($unpack_dir | path join $name)

  mkdir $dst_dir

  try {
    do { cd $dst_dir; ^sigtool --unpack=($cvd_path | path expand) } | ignore
  } catch {}

  try {
    ^sigtool --info=($cvd_path | path expand) | save -f ($dst_dir | path join "info.txt")
  } catch {}
}

def unpack_all_db_files [dbdir: string, unpack_dir: string] {
  ensure_empty_dir $unpack_dir

  for cvd_path in (list_db_files $dbdir) {
    unpack_db_file $cvd_path $unpack_dir
  }
}

def copy_dns_txt [dbdir: string, unpack_dir: string] {
  let dns_txt = ($dbdir | path join "dns.txt")
  if ($dns_txt | path exists) {
    cp $dns_txt $unpack_dir
  }
}

def list_files_recursive [dir: string] {
  glob ($dir | path join "**")
    | where {|p| ($p | path type) == "file" }
    | sort
}

def enforce_size_limit [dir: string, size_limit_bytes: int] {
  for file_path in (list_files_recursive $dir) {
    let size = (ls -l $file_path | get 0.size | into int)
    if $size > $size_limit_bytes {
      let hash = (sha256 $file_path)
      rm -f $file_path
      let placeholder_path = $"($file_path).placeholder"
      $"oid sha256:($hash)\nsize ($size)\n" | save -f $placeholder_path
    }
  }
}

def stage_path [path: string] {
  ^git add -A -- $path
}

def staged_changes_exist [path: string] {
  (^git status --porcelain -- $path | str trim) != ""
}

def configure_git_author [] {
  ^git config user.name "github-actions[bot]"
  ^git config user.email "github-actions[bot]@users.noreply.github.com"
}

def commit_and_push [timestamp: string] {
  configure_git_author
  ^git commit -m $"feat: bump [($timestamp)]"
  ^git push
}

def main [
  --dbdir: string
  --unpack-dir: string
  --size-limit-bytes: int
] {
  let effective_dbdir = ($dbdir | default ($env.DBDIR? | default "out"))
  let effective_unpack_dir = ($unpack_dir | default ($env.UNPACK_DIR? | default "freshclam"))
  let effective_size_limit = (
    if $size_limit_bytes != null {
      $size_limit_bytes
    } else {
      (($env.SIZE_LIMIT_BYTES? | default "52428800") | into int)
    }
  )

  update_db $effective_dbdir

  let timestamp = (now_utc_timestamp)
  write_github_output "timestamp" $timestamp

  unpack_all_db_files $effective_dbdir $effective_unpack_dir
  copy_dns_txt $effective_dbdir $effective_unpack_dir
  enforce_size_limit $effective_unpack_dir $effective_size_limit

  stage_path $effective_unpack_dir
  if not (staged_changes_exist $effective_unpack_dir) {
    exit 0
  }

  commit_and_push $timestamp
}
