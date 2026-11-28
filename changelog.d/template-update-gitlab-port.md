### Fixed

- [`/plinth:template-update`](https://github.com/coolbress/plinth/blob/main/skills/template-update/SKILL.md)
  on a self-hosted GitLab served on its own HTTPS port (an origin like
  `https://gitlab.example.com:8443/group/project.git`) asks that port, where
  it asked port 443 and stopped (#1152). glab takes no port in `--hostname`,
  so the port goes to it as `GITLAB_API_HOST=<host>:<port>`, in the reads and
  in the commands it prints for a Maintainer. glab's login for that GitLab is
  the one made with `glab auth login --hostname <host> --api-host
  <host>:<port>`, as the stop names. An `ssh://` origin's port is the SSH
  server's and is still not used for the API.
