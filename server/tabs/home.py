import streamlit as st

st.title("LeanAide Server [![Repo](https://badgen.net/badge/icon/LeanAide?icon=github&label)](https://github.com/siddhartha-gadgil/LeanAide)", anchor = "LeanAide Server")

with st.sidebar:
    st.title("LeanAide Services")
    st.success("Please select a task page above.")
    st.divider()

st.write("LeanAide Streamlit Server provides a user interface for interacting with LeanAide server.")

st.header("Utilities", divider = True, anchor = "Utilities")
st.write(
"""
To use different services, you can visit the different pages in the sidebar.

- `Server Response`: POST requests to the server and get response.
- `Structured Json`: Input your theorem & proof(or generate it using LLM's) and obtain structured JSON output based on LeanAide Schema's.
- `Logs`: View the Server and Streamlit logs.

Visit the official GitHub [LeanAide](https://github.com/siddhartha-gadgil/LeanAide) repository for more information and documentation.
"""
)

st.divider()
st.subheader("Tips on using the server")
st.write(
"""
`1.` Check the help text on each option by hovering or clicking the question mark icon next to it.\n
`2.` Input Host Information or LLM Credentials in the sidebar to configure the server.\n
`3.` If your sent request takes too long to get output(when you know it shoudn't), Wait a bit or **Refresh** and try again.\n
`4.` If you encounter any issues, check the logs for more information.

""")
st.divider()
