import os
import requests
import jenkins
import time

GITHUB_ACCESS_TOKEN = os.getenv('GITHUB_ACCESS_TOKEN')
JENKINS_URL = "https://jenkins.macuartin.com"
JENKINS_USERNAME = os.getenv('JENKINS_USERNAME')
JENKINS_PASSWORD = os.getenv('JENKINS_PASSWORD')

PACKAGE_MANAGER={'Ruby': 'bundler',
                 'Python': 'pip' '(includes pipenv)',
                 'HTML': 'npm_and_yarn',
                 'JavaScript': 'npm_and_yarn',
                 'TypeScript': 'npm_and_yarn',
                 'Java': 'gradle',
                 'Go': 'go_modules',
                 'Docker': 'docker',
                 'HCL': 'terraform'}

class DevOpsJenkins:
    def __init__(self):
        self.jenkins_server = jenkins.Jenkins(JENKINS_URL, username=JENKINS_USERNAME, password=JENKINS_PASSWORD)
        user = self.jenkins_server.get_whoami()
        version = self.jenkins_server.get_version()
        print ("Jenkins Version: {}".format(version))
        print ("Jenkins User: {}".format(user['id']))

    def build_job(self, name, parameters=None, token=None):
        next_build_number = self.jenkins_server.get_job_info(name)['nextBuildNumber']
        self.jenkins_server.build_job(name, parameters=parameters, token=token)
        time.sleep(10)
        build_info = self.jenkins_server.get_build_info(name, next_build_number)
        return build_info


if __name__=='__main__':
    
    NAME_OF_JOB = "dependabot"
    TOKEN_NAME = "228AED1CEF19417DCE711CB5281A6"
    jenkins_obj = DevOpsJenkins()

    try:
        response = requests.get('https://api.github.com/users/cuartinm/repos', headers={'Authorization': 'token {}'.format(GITHUB_ACCESS_TOKEN), 'Accept': 'application/vnd.github.v3+json'})
        for repo in response.json():
            PARAMETERS = {'PROJECT_PATH': repo['full_name'], 'PACKAGE_MANAGER': PACKAGE_MANAGER[repo['language']]}
            output = jenkins_obj.build_job(NAME_OF_JOB, PARAMETERS, TOKEN_NAME)
            print ("Jenkins Build URL: {}".format(output['url']))
    except requests.exceptions.HTTPError as error:
        print(error)