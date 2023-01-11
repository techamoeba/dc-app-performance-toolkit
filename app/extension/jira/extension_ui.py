import random

from selenium.webdriver.common.by import By

from selenium_ui.base_page import BasePage
from selenium_ui.conftest import print_timing
from selenium_ui.jira.pages.pages import Login
from util.conf import JIRA_SETTINGS


def app_specific_action(webdriver, datasets):
    page = BasePage(webdriver)
    project_key=datasets['project_key']
    # To run action as specific user uncomment code bellow.
    # NOTE: If app_specific_action is running as specific user, make sure that app_specific_action is running
    # just before test_2_selenium_z_log_out action
    #
    # @print_timing("selenium_app_specific_user_login")
    # def measure():
    #     def app_specific_user_login(username='admin', password='admin'):
    #         login_page = Login(webdriver)
    #         login_page.delete_all_cookies()
    #         login_page.go_to()
    #         login_page.set_credentials(username=username, password=password)
    #         if login_page.is_first_login():
    #             login_page.first_login_setup()
    #         if login_page.is_first_login_second_page():
    #             login_page.first_login_second_page_setup()
    #         login_page.wait_for_page_loaded()
    #     app_specific_user_login(username='admin', password='admin')
    # measure()

    @print_timing("selenium_app_custom_action")
    def measure():
        @print_timing("selenium_app_custom_action:arn_project_context_view")
        def sub_measure():
            page.go_to_url(f"{JIRA_SETTINGS.server_url}/projects/{project_key}?selectedItem=com.atlassian.jira.jira-projects-plugin:automated_release_notes_page&projectKey={project_key}#/rules/list")
            page.wait_until_visible((By.CSS_SELECTOR, "div[role='tablist']"))  # Wait till tabs are loaded
            page.wait_until_visible((By.CSS_SELECTOR, "div[role='tabpanel']")) # Wait till tabpanel is loaded
        sub_measure()
    measure()

