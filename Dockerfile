FROM harbor.klaus.com/bookmanage/tomcat:jdk8
COPY target/*.war /usr/local/tomcat/webapps/ROOT.war
