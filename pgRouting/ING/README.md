# ING ATM study

For this study we need to get the 2 nearest Popular Bank ATMs (ING partners) to each and every ATM in Spain. Due to high time cost of processing each ATM against the other 30K with pgRouting, we have first found the nearest 5 ATMs in terms of linear distance, and then get the nearest 2 out of those 5 in terms of routed distance.

```sh
time psql -U postgres -d cartodb_user_..._db -c "SELECT * FROM ing_launch('output_table', numbner_of_cores);";

```
