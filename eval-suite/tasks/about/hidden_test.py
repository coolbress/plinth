from django.test import Client


def test_hidden_about_page_public() -> None:
    client = Client()
    codes = {}
    for url in ("/about/", "/about"):
        response = client.get(url, secure=True)
        codes[url] = response.status_code
        if response.status_code == 200 and response.content.strip():
            return
    raise AssertionError(f"no public About page: {codes}")
