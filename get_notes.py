import requests
from jira import JIRA
from os import environ as env
from collections import defaultdict

env['JIRA_USER'] = "shevchenkcoigor@gmail.com"
env['JIRA_TOKEN'] = "ATATT3xFfGF08poOg-ZvIu7C3p-wr_j7kKZw4EFs__Jz5TSuWbWS4fZUfJJhAKWgwA9wzzznR2E2TFpHGlB2jwd7Ph440N8-94aoRY6Hwza9zZKYOLMW91qHvvPeffiVBSexom4hM1b26lOM3Bi29tAKzGSp7chhV319kqI8espkwu5wk3rr1OI=4565A944"
env['JIRA_HOST'] = "https://cross-bible.atlassian.net"
env['VERSION'] = "v1.0.0"


def get_notes_from_jira():
    jira = JIRA(env['JIRA_HOST'], basic_auth=(env['JIRA_USER'], env['JIRA_TOKEN']))
    issues = jira.search_issues(f"project=FB and fixVersion={env['VERSION']}")

    with requests.sessions.Session() as session:
        session.auth = (env['JIRA_USER'], env['JIRA_TOKEN'])
        d = defaultdict(list)

        for issue in issues:
            d[issue.fields.issuetype].append(issue)

        notes_list = []

        for group, issues in d.items():
            notes_list.append("<details>")

            notes_list.append(f"<summary>{group}</summary>\n")
            for issue in issues:
                res = session.get(
                    f"{env['JIRA_HOST']}/rest/dev-status/1.0/issue/details?issueId={int(issue.id)}"
                    f"&applicationType=github&dataType=pullrequest")
                j = res.json()
                pull_requests = j['detail'][0]['pullRequests']
                pull_request = pull_requests[0]['url'] if pull_requests else ""
                notes_list.append(f"* [{issue.key}]({issue.permalink()}); {issue.fields.summary}; @spiritEcosse in {pull_request}")
            notes_list.append("</details>")
        notes_list.append("\n## Other")
        notes_list.append(
            f"**Full Changelog**: https://github.com/spiritEcosse/bible/commits/{env['VERSION']}")

    notes = "\n".join(notes_list)
    return notes


if __name__ == "__main__":
    print(get_notes_from_jira())
