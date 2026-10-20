# canary-web

The `web` archetype as plinth-template renders it, so this repository can run
its reusable CI workflow on a Django project for real. Nothing here is a
product.
The container entry point (`__main__.py`) is left out: python-ci does not
run it; the template's own `image` job does.
