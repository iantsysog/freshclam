module constants {
    export const DEFAULT_DATABASE_DIRECTORY = "out"
    export const DEFAULT_UNPACK_DIRECTORY = "freshclam"
    export const DEFAULT_SIZE_LIMIT_BYTES = 52428800

    export const UTC_TIMEZONE = "UTC"
    export const ISO_TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

    export const SIGNATURE_DATABASE_EXTENSIONS = ["cvd" "cld"]
    export const DNS_FILENAME = "dns.txt"
    export const INFO_FILENAME = "info.txt"

    export const PLACEHOLDER_EXTENSION = "placeholder"
    export const PLACEHOLDER_HASH_PREFIX = "oid sha256:"
    export const PLACEHOLDER_SIZE_PREFIX = "size "
    export const TEXT_LINE_SEPARATOR = "\n"

    export const COMMIT_MESSAGE_PREFIX = "feat: bump ["
    export const COMMIT_MESSAGE_SUFFIX = "]"

    export const GIT_AUTHOR_NAME = "github-actions[bot]"
    export const GIT_AUTHOR_EMAIL = "github-actions[bot]@users.noreply.github.com"

    export const GIT_OUTPUT_KEY_TIMESTAMP = "timestamp"
    export const GITHUB_OUTPUT_ENVIRONMENT_VARIABLE = "GITHUB_OUTPUT"
    export const DBDIR_ENVIRONMENT_VARIABLE = "DBDIR"
    export const UNPACK_DIR_ENVIRONMENT_VARIABLE = "UNPACK_DIR"
    export const SIZE_LIMIT_ENVIRONMENT_VARIABLE = "SIZE_LIMIT_BYTES"

    export const DIRECTORY_PATH_TYPE = "dir"
    export const FILE_PATH_TYPE = "file"

    export const RECURSIVE_GLOB_PATTERN = "**"
    export const EXTENSION_GLOB_PATTERN = "*."

    export const FILENAME_EXTENSION_SEPARATOR = "."
    export const KEY_VALUE_SEPARATOR = "="
    export const TOKEN_SEPARATOR = " "
    export const REGEX_EXTENSION_GROUP_OPEN = "\\.("
    export const REGEX_EXTENSION_GROUP_CLOSE = ")$"
    export const REGEX_EXTENSION_SEPARATOR = "|"

    export const CVD_COMMAND = "cvd"
    export const CVD_CONFIG_COMMAND = "config"
    export const CVD_SET_COMMAND = "set"
    export const CVD_DATABASE_DIRECTORY_FLAG = "--dbdir"
    export const CVD_UPDATE_COMMAND = "update"

    export const SIGTOOL_COMMAND = "sigtool"
    export const SIGTOOL_UNPACK_FLAG = "--unpack="
    export const SIGTOOL_INFO_FLAG = "--info="

    export const GIT_COMMAND = "git"
    export const GIT_ADD_COMMAND = "add"
    export const GIT_ALL_FLAG = "-A"
    export const GIT_STATUS_COMMAND = "status"
    export const GIT_PORCELAIN_FLAG = "--porcelain"
    export const GIT_COMMIT_COMMAND = "commit"
    export const GIT_MESSAGE_FLAG = "-m"
    export const GIT_CONFIG_COMMAND = "config"
    export const GIT_NAME_SETTING = "user.name"
    export const GIT_EMAIL_SETTING = "user.email"
    export const GIT_PUSH_COMMAND = "push"

    export const SHA256SUM_COMMAND = "sha256sum"
    export const SHA256SUM_FILE_FLAG = "--"
    export const SHASUM_COMMAND = "shasum"
    export const SHASUM_ALGORITHM_FLAG = "-a"
    export const SHASUM_ALGORITHM_CODE = "256"
    export const SHASUM_FILE_FLAG = "--"
}

module filesystem {
    use constants *

    export def join-path [base: string, segment: string] { $base | path join $segment }
    export def base-name [path: string] { $path | path basename }
    export def expand-path [path: string] { $path | path expand }

    export def directory-exists [path: string] { ($path | path exists) and (($path | path type) == $DIRECTORY_PATH_TYPE) }
    export def file-exists [path: string] { ($path | path exists) and (($path | path type) == $FILE_PATH_TYPE) }

    export def remove-directory-recursive [dir: string] { rm -rf $dir }
    export def remove-file [path: string] { rm -f $path }
    export def copy-file [source: string, destination: string] { cp $source $destination }
    export def write-text-to-file [text: string, path: string] { $text | save -f $path }
    export def append-text-to-file [text: string, path: string] { $text | save -a $path }

    export def file-size-bytes [path: string] { ls -l $path | get 0.size | into int }

    export def ensure-empty-directory [dir: string] {
        if (directory-exists $dir) { remove-directory-recursive $dir }
        mkdir $dir
    }

    export def copy-file-if-present [source: string, destination: string] {
        if (file-exists $source) { copy-file $source $destination }
    }

    export def glob-files [pattern: string] { glob $pattern }

    export def glob-files-with-extension [dir: string, ext: string] {
        glob-files (join-path $dir ($EXTENSION_GLOB_PATTERN + $ext))
    }

    export def list-files-recursively [dir: string] {
        glob-files (join-path $dir $RECURSIVE_GLOB_PATTERN)
            | where {|path| file-exists $path }
            | sort
    }

    export def append-line-separator [] { $in + $TEXT_LINE_SEPARATOR }
}

module text-processing {
    use constants *

    export def first-line [] { $in | lines | first }
    export def first-word [] { $in | split row $TOKEN_SEPARATOR | first }
    export def join-with-extension-separator [extensions: list] { $extensions | str join $REGEX_EXTENSION_SEPARATOR }
    export def regex-extension-pattern [extensions: list] {
        $REGEX_EXTENSION_GROUP_OPEN + (join-with-extension-separator $extensions) + $REGEX_EXTENSION_GROUP_CLOSE
    }
}

module hashing {
    use filesystem expand-path
    use text-processing *
    use constants *

    def command-exists [name: string] { (which $name | length) > 0 }

    def hash-provider [name: string, execute: closure] { {name: $name, execute: $execute} }

    def hash-provider-sha256sum [] {
        hash-provider $SHA256SUM_COMMAND {|path: string|
            ^$SHA256SUM_COMMAND $SHA256SUM_FILE_FLAG $path | first-line | first-word
        }
    }

    def hash-provider-shasum [] {
        hash-provider $SHASUM_COMMAND {|path: string|
            ^$SHASUM_COMMAND $SHASUM_ALGORITHM_FLAG $SHASUM_ALGORITHM_CODE $SHASUM_FILE_FLAG $path | first-line | first-word
        }
    }

    def hash-providers [] { [(hash-provider-sha256sum) (hash-provider-shasum)] }

    def available-hash-providers [] { (hash-providers) | where {|provider| command-exists $provider.name} }

    export def hash-file [path: string] {
        let provider = (available-hash-providers | first)
        do $provider.execute (expand-path $path)
    }
}

module environment {
    use filesystem *
    use constants *

    def github-output-path [] { $env | get --optional $GITHUB_OUTPUT_ENVIRONMENT_VARIABLE }

    def key-value-line [key: string, value: string] { $"($key)($KEY_VALUE_SEPARATOR)($value)" | append-line-separator }

    export def append-github-output [key: string, value: string] {
        let path = github-output-path
        if $path != null {
            append-text-to-file (key-value-line $key $value) $path
        }
    }

    export def env-string [name: string] { $env | get --optional $name }

    export def env-int [name: string] {
        let value = env-string $name
        if $value == null { null } else { $value | into int }
    }
}

module external-tools {
    use filesystem *
    use constants *

    def configure-cvd-database-directory [dbdir: string] {
        ^$CVD_COMMAND $CVD_CONFIG_COMMAND $CVD_SET_COMMAND $CVD_DATABASE_DIRECTORY_FLAG $dbdir
    }

    def update-cvd-database [] { ^$CVD_COMMAND $CVD_UPDATE_COMMAND }

    export def refresh-virus-database [dbdir: string] {
        configure-cvd-database-directory $dbdir
        update-cvd-database
    }

    def execute-in-directory [dir: string, operation: closure] { cd $dir; do $operation }
    def suppress-errors [operation: closure] { try { do $operation } catch {} }

    def attempt-unpack-signature-database [source: string, destination: string] {
        suppress-errors {
            execute-in-directory $destination {
                ^$SIGTOOL_COMMAND ($SIGTOOL_UNPACK_FLAG + (expand-path $source)) | ignore
            }
        }
    }

    def write-signature-database-info [source: string, destination: string] {
        suppress-errors {
            ^$SIGTOOL_COMMAND ($SIGTOOL_INFO_FLAG + (expand-path $source)) | save -f (join-path $destination $INFO_FILENAME)
        }
    }

    export def unpack-signature-database [source: string, destination: string] {
        attempt-unpack-signature-database $source $destination
        write-signature-database-info $source $destination
    }

    export def stage-path [path: string] { ^$GIT_COMMAND $GIT_ADD_COMMAND $GIT_ALL_FLAG -- $path }

    export def staged-changes-exist-for [path: string] {
        (^$GIT_COMMAND $GIT_STATUS_COMMAND $GIT_PORCELAIN_FLAG -- $path | str trim) != ""
    }

    export def configure-git-author [] {
        ^$GIT_COMMAND $GIT_CONFIG_COMMAND $GIT_NAME_SETTING $GIT_AUTHOR_NAME
        ^$GIT_COMMAND $GIT_CONFIG_COMMAND $GIT_EMAIL_SETTING $GIT_AUTHOR_EMAIL
    }

    def mirror-commit-message [timestamp: string] {
        $"($COMMIT_MESSAGE_PREFIX)($timestamp)($COMMIT_MESSAGE_SUFFIX)"
    }

    export def commit-mirror-update [timestamp: string] {
        ^$GIT_COMMAND $GIT_COMMIT_COMMAND $GIT_MESSAGE_FLAG (mirror-commit-message $timestamp)
    }

    export def push-commits [] { ^$GIT_COMMAND $GIT_PUSH_COMMAND }
}

module database {
    use filesystem *
    use external-tools *
    use text-processing regex-extension-pattern
    use constants *

    export def signature-database-name [path: string] {
        base-name $path | str replace -r (regex-extension-pattern $SIGNATURE_DATABASE_EXTENSIONS) ""
    }

    export def list-signature-databases [dbdir: string] {
        $SIGNATURE_DATABASE_EXTENSIONS
            | each {|extension| glob-files-with-extension $dbdir $extension }
            | flatten
            | sort
    }

    export def unpack-database-to [source: string, unpack_dir: string] {
        let destination = join-path $unpack_dir (signature-database-name $source)
        ensure-empty-directory $destination
        unpack-signature-database $source $destination
    }

    export def unpack-all-databases-to [dbdir: string, unpack_dir: string] {
        ensure-empty-directory $unpack_dir
        list-signature-databases $dbdir | each {|source| unpack-database-to $source $unpack_dir }
    }

    export def copy-dns-record-to [dbdir: string, unpack_dir: string] {
        copy-file-if-present (join-path $dbdir $DNS_FILENAME) $unpack_dir
    }
}

module sanitization {
    use filesystem *
    use hashing hash-file
    use constants *

    def oversized? [size: int, limit: int] { $size > $limit }
    def placeholder-path-for [path: string] { $path + $FILENAME_EXTENSION_SEPARATOR + $PLACEHOLDER_EXTENSION }
    def placeholder-hash-field [hash: string] { $PLACEHOLDER_HASH_PREFIX + $hash }
    def placeholder-size-field [size: int] { $PLACEHOLDER_SIZE_PREFIX + ($size | into string) }

    def placeholder-content-for [hash: string, size: int] {
        [(placeholder-hash-field $hash) (placeholder-size-field $size)]
            | str join $TEXT_LINE_SEPARATOR
            | append-line-separator
    }

    def replace-file-with-placeholder [path: string, limit: int] {
        let size = file-size-bytes $path
        if (oversized? $size $limit) {
            let hash = hash-file $path
            remove-file $path
            write-text-to-file (placeholder-content-for $hash $size) (placeholder-path-for $path)
        }
    }

    export def sanitize-oversized-files-in-directory [dir: string, limit: int] {
        list-files-recursively $dir | each {|file| replace-file-with-placeholder $file $limit }
    }
}

module configuration {
    use environment *
    use constants *

    def first-present-value [candidates: list] { $candidates | where {|candidate| $candidate != null } | first }

    def resolve-database-directory [cli_value: any] {
        first-present-value [$cli_value, (env-string $DBDIR_ENVIRONMENT_VARIABLE), $DEFAULT_DATABASE_DIRECTORY]
    }

    def resolve-unpack-directory [cli_value: any] {
        first-present-value [$cli_value, (env-string $UNPACK_DIR_ENVIRONMENT_VARIABLE), $DEFAULT_UNPACK_DIRECTORY]
    }

    def resolve-size-limit-bytes [cli_value: any] {
        if $cli_value != null {
            $cli_value
        } else {
            first-present-value [(env-int $SIZE_LIMIT_ENVIRONMENT_VARIABLE), $DEFAULT_SIZE_LIMIT_BYTES]
        }
    }

    export def build-mirror-configuration [cli_dbdir: any, cli_unpack_dir: any, cli_size_limit: any] {
        {
            database-directory: (resolve-database-directory $cli_dbdir)
            unpack-directory: (resolve-unpack-directory $cli_unpack_dir)
            size-limit-bytes: (resolve-size-limit-bytes $cli_size_limit)
        }
    }
}

module orchestration {
    use environment *
    use external-tools *
    use database *
    use sanitization *
    use constants *

    export def timestamp-now-utc [] {
        date now | date to-timezone $UTC_TIMEZONE | format date $ISO_TIMESTAMP_FORMAT
    }

    export def record-mirror-timestamp [timestamp: string] {
        append-github-output $GIT_OUTPUT_KEY_TIMESTAMP $timestamp
    }

    export def mirror-databases [dbdir: string, unpack_dir: string] {
        unpack-all-databases-to $dbdir $unpack_dir
        copy-dns-record-to $dbdir $unpack_dir
    }

    export def publish-mirror-changes [path: string, timestamp: string] {
        stage-path $path
        if (staged-changes-exist-for $path) {
            configure-git-author
            commit-mirror-update $timestamp
            push-commits
        }
    }

    export def execute-mirror-workflow [config: record] {
        refresh-virus-database $config.database-directory

        let timestamp = timestamp-now-utc
        record-mirror-timestamp $timestamp

        mirror-databases $config.database-directory $config.unpack-directory
        sanitize-oversized-files-in-directory $config.unpack-directory $config.size-limit-bytes

        publish-mirror-changes $config.unpack-directory $timestamp
    }
}

use configuration build-mirror-configuration
use orchestration execute-mirror-workflow

def main [
    --dbdir: string
    --unpack-dir: string
    --size-limit-bytes: int
] {
    let config = build-mirror-configuration $dbdir $unpack_dir $size_limit_bytes
    execute-mirror-workflow $config
}
