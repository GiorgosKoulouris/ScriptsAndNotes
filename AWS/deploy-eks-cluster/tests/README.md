<h1>Under development</h1>

<h2>Information</h2>

This section contains code that is not meant to be executed as a whole script. It is a list of items that are currently being tested.

Execute the commands of the files one by one and modify accordingly.

<h2>Code Sections</h2>

<h3>Annotate kubernetes ServiceAccount with an IAM role</h3>

Create a kubernetes service account and annotate it with an IAM role.

<b>Testing:</b> Attach the service account to any pod you want to have access to AWS services.

<h3>Bind a kubernetes ServiceAccount with a kubernetes role</h3>

Create a service account in kubernetes, a custom role with specific permissions in the cluster and bind them.

<b>Testing:</b> Attach the service account to any pod you want to have access to the cluster's api.

