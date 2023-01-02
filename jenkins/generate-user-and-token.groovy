import hudson.model.*
import jenkins.model.*
import jenkins.security.*
import jenkins.security.apitoken.*

// script parameters
def userName = 'jenkins'
def tokenName = 'jenkins-token'

jenkins.model.Jenkins.instance.securityRealm.createAccount('jenkins', 'cL3ar#12')
  
def user = User.get(userName, false)
def apiTokenProperty = user.getProperty(ApiTokenProperty.class)
def result = apiTokenProperty.tokenStore.generateNewToken(tokenName)
user.save()

println result.plainValue
return result.plainValue
