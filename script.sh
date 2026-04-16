import requests

url = "https://litellm.qa.in.spdigital.sg/models"

headers = {
    "Authorization": "Bearer sk-677s9TsQeLwaZF1W_8dfyg"
}

response = requests.get(url, headers=headers)

print(f"Status Code: {response.status_code}")
print(response.json())
