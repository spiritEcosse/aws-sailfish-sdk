import requests
from jira import JIRA
from os import environ as env
from collections import defaultdict


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
                pull_request = j['detail'][0]['pullRequests'][0]['url'] if j['detail'] else ""
                last_commit = j['detail'][0]['branches'][0]['lastCommit']['url'] if j['detail'] else ""
                notes_list.append(f"* [{issue.key}]({issue.permalink()}); {issue.fields.summary}; @spiritEcosse in {pull_request}; commit: {last_commit}")
            notes_list.append("</details>")
        notes_list.append("\n## Other")
        notes_list.append(
            f"**Full Changelog**: https://github.com/spiritEcosse/bible/commits/{env['VERSION']}")

    notes = "\n".join(notes_list)
    return notes


if __name__ == "__main__":
    print(get_notes_from_jira())
