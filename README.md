# apim-logicapp-demo

```
CREATE TABLE terms (
	ID int NOT NULL IDENTITY PRIMARY KEY,
    term VARCHAR(50),
    termDefinition VARCHAR(500),
	createdDate DATETIME DEFAULT GETDATE(),
	updatedDate DATETIME DEFAULT GETDATE(),
);
```

```
{
    "term": "vnet",
    "definition": "virtual network"
}
```